# frozen_string_literal: true

module Manage
  module Staffing
    # A shift someone can't make, the performer flow's way (Tim, 2026-11-02):
    # the page where a manager finds cover. Who dropped it and why, who to
    # ask (the staff scope of the People Picker, free people first), an
    # editable invitation with a claim link each, assigning someone by hand
    # instead, not filling it, or putting the person back. Once settled, one
    # closure card, with Tell now for cover who hasn't heard.
    class VacanciesController < Manage::ManageController
      before_action :ensure_org_owner_or_manager
      before_action :set_vacancy

      def show
        @shift = @vacancy.shift
        @invitations = @vacancy.invitations.includes(person: ShiftCandidates::HEADSHOTS).order(created_at: :desc).to_a
        @others_on_shift = @shift.active_assignments.map(&:person)
        return unless @vacancy.active?

        @candidates = ShiftCandidates.new(@shift, exclude_keys: [ "Person_#{@vacancy.vacated_by_id}" ], exclude_label: "Can't make it",
                                                  invited_ids: @invitations.map(&:person_id))
        # The draft reads as the shift's own words (the role, the hours, the
        # shows); only each person's name and claim link stay as tokens, and
        # the page says so under the box.
        variables = ShiftVacancyNotificationService.invitation_variables(@vacancy)
        @email_draft = EmailDraft.new(title: ContentTemplate.interpolate(template.subject, variables),
                                      body: ContentTemplate.interpolate(template.body, variables))
      end

      # The chosen people each get the manager's words with a claim link of
      # their own; the first to claim gets the shift. The email always goes:
      # it carries the link they need, as a contract's does.
      def send_invitations
        unless @vacancy.active?
          redirect_to manage_staffing_vacancy_path(@vacancy), alert: "This shift is no longer open." and return
        end

        ids = Array(params[:member_ids]).map { |k| k.to_s.delete_prefix("Person_").to_i }.reject(&:zero?).uniq
        people = Person.joins(:organization_staff_members)
                       .where(organization_staff_members: { organization_id: Current.organization.id, archived_at: nil })
                       .where(id: ids).distinct.to_a
        people.select! { |person| @vacancy.can_invite?(person) }
        if people.empty?
          redirect_to manage_staffing_vacancy_path(@vacancy), alert: "Choose at least one person to ask." and return
        end

        draft = params[:email_draft] || {}
        variables = ShiftVacancyNotificationService.invitation_variables(@vacancy)
        subject = ContentTemplate.interpolate(draft[:title].presence || template.subject, variables)
        body = ContentTemplate.interpolate(draft[:body].to_s.presence || template.body, variables)

        batch = if people.size > 1
          EmailBatch.create!(user: Current.user, subject: subject, recipient_count: people.size, sent_at: Time.current)
        end
        people.each do |person|
          invitation = @vacancy.invitations.create!(person: person, email_subject: subject, email_body: body)
          ShiftVacancyInvitationMailer.invitation_email(invitation, email_batch_id: batch&.id).deliver_later
        end
        @vacancy.mark_finding_replacement!

        redirect_to manage_staffing_vacancy_path(@vacancy),
                    notice: "Asked #{people.size == 1 ? people.first.name : helpers.pluralize(people.size, 'person')} to cover the shift."
      end

      # Not filling it: the hole closes and the schedule's red goes.
      def cancel
        if @vacancy.mark_not_filling!(by: Current.user)
          redirect_to manage_staffing_scheduling_path(day: @vacancy.shift.starts_at.to_date.iso8601),
                      notice: "Not filling the #{@vacancy.shift.role_label} shift #{@vacancy.vacated_by.name} couldn't make."
        else
          redirect_to manage_staffing_vacancy_path(@vacancy), alert: "This shift is no longer open."
        end
      end

      # Put them back on it.
      def reclaim
        if @vacancy.reclaim!(by: Current.user)
          redirect_to manage_staffing_scheduling_path(day: @vacancy.shift.starts_at.to_date.iso8601),
                      notice: "#{@vacancy.vacated_by.name} is back on the #{@vacancy.shift.role_label} shift."
        else
          redirect_to manage_staffing_vacancy_path(@vacancy), alert: "This shift has already been covered or closed."
        end
      end

      # Whoever was put on by hand before a pick told them at once (or while
      # nothing could reach them): tell them now, from the closed page, so
      # nobody has to remember Notify updates for it (Tim, 2026-11-10).
      def tell_cover
        cover = @vacancy.filled_by if @vacancy.filled?
        row = cover && @vacancy.shift.shift_assignments.active.find_by(person_id: cover.id)
        if row && @vacancy.shift.ends_at.future? && StaffScheduleNotices.tell_new_shift!(row)
          redirect_to manage_staffing_vacancy_path(@vacancy), notice: "#{cover.name.to_s.split.first} has been told."
        else
          redirect_to manage_staffing_vacancy_path(@vacancy), alert: "Nothing was sent: they've been told already, or can't be reached yet."
        end
      end

      private

      def set_vacancy
        @vacancy = ShiftVacancy.joins(:shift)
                               .where(shifts: { organization_id: Current.organization.id })
                               .includes(shift: [ :house_role, :organization, :source, { shift_assignments: { person: ShiftCandidates::HEADSHOTS } }, { shows: :production } ],
                                         vacated_by: ShiftCandidates::HEADSHOTS, filled_by: ShiftCandidates::HEADSHOTS)
                               .find(params[:id])
      end

      def template
        @template ||= ContentTemplate.active.find_by(key: "shift_vacancy_invitation") ||
                      ContentTemplate.new(subject: "Can you cover a {{role_name}} shift on {{shift_date}}?",
                                          body: "<p>Hi {{recipient_name}}, {{organization_name}} needs someone on {{role_name}}: {{shift_info}}.</p><p><a href=\"{{claim_url}}\">Claim this shift</a></p>")
      end
    end
  end
end

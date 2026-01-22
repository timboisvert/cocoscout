# frozen_string_literal: true

module Manage
  class VacanciesController < Manage::ManageController
    before_action :set_production
    before_action :check_production_access
    before_action :set_vacancy, only: %i[show send_invitations cancel fill]

    def show
      @invitations = @vacancy.invitations.includes(:person).order(created_at: :desc)

      # Get eligible members (people and groups) to invite from effective talent pool
      @talent_pool = @production.effective_talent_pool

      # Always get all talent pool members - even for restricted roles,
      # users should be able to choose anyone (restrictions are advisory)
      people = @talent_pool.people.includes(profile_headshots: { image_attachment: :blob })
      groups = @talent_pool.groups.includes(profile_headshots: { image_attachment: :blob })
      all_members = (people.to_a + groups.to_a)

      # Track which members are "role-eligible" for restricted roles (for UI indication)
      @role_eligible_member_keys = Set.new
      if @vacancy.restricted?
        @vacancy.eligible_members.each do |member|
          @role_eligible_member_keys << "#{member.class.name}_#{member.id}"
        end
      end

      # Track the member who vacated the role (to show grayed out)
      @vacated_by_id = @vacancy.vacated_by_id
      @vacated_by_type = @vacancy.vacated_by_type

      # Track members who have already been invited (to show grayed out)
      # Note: Currently invitations only support people, not groups
      @already_invited_person_ids = @vacancy.invitations.pluck(:person_id)

      # Track members who already have a role in this show (to show grayed out)
      @already_cast_person_ids = @vacancy.show.show_person_role_assignments
                                              .where(assignable_type: "Person")
                                              .pluck(:assignable_id)
      @already_cast_group_ids = @vacancy.show.show_person_role_assignments
                                             .where(assignable_type: "Group")
                                             .pluck(:assignable_id)

      # Sort: role-eligible first (for restricted roles), unavailable at bottom, then by name
      @all_potential_members = all_members.sort_by do |member|
        is_vacated = member.class.name == @vacated_by_type && member.id == @vacated_by_id
        is_already_cast = member.is_a?(Person) ? @already_cast_person_ids.include?(member.id) : @already_cast_group_ids.include?(member.id)
        is_already_invited = member.is_a?(Person) && @already_invited_person_ids.include?(member.id)
        is_unavailable = is_vacated || is_already_cast || is_already_invited
        is_role_eligible = @role_eligible_member_keys.include?("#{member.class.name}_#{member.id}")
        [
          is_unavailable ? 2 : (is_role_eligible ? 0 : 1),  # eligible first, then others, unavailable last
          member.name.downcase
        ]
      end

      # Members who can actually be invited (excludes already cast, already invited, and vacated)
      @eligible_members = @all_potential_members.reject do |member|
        is_vacated = member.class.name == @vacated_by_type && member.id == @vacated_by_id
        is_already_cast = member.is_a?(Person) ? @already_cast_person_ids.include?(member.id) : @already_cast_group_ids.include?(member.id)
        is_already_invited = member.is_a?(Person) && @already_invited_person_ids.include?(member.id)
        is_vacated || is_already_cast || is_already_invited
      end

      # For backward compatibility (used in unrestricted roles radio option count)
      @eligible_people = @eligible_members.select { |m| m.is_a?(Person) }

      # Get other cast members for display (excluding the person who vacated)
      @other_cast_assignments = @vacancy.show.show_person_role_assignments
                                            .includes(:role)
                                            .where.not(
                                              assignable_type: @vacated_by_type,
                                              assignable_id: @vacated_by_id
                                            )
                                            .order("roles.position ASC")
      @all_potential_people = @all_potential_members.select { |m| m.is_a?(Person) }

      # Create email draft for invitation form
      @vacancy_email_draft = EmailDraft.new(
        title: default_vacancy_email_subject,
        body: default_vacancy_email_body
      )
    end

    def send_invitations
      invite_mode = params[:invite_mode]

      # Get email content from EmailDraft form fields
      email_draft_params = params[:email_draft] || {}
      email_subject = email_draft_params[:title].presence || default_vacancy_email_subject
      email_body = email_draft_params[:body].to_s.presence || default_vacancy_email_body

      # IDs to exclude: already invited, already cast in this show, or the person who vacated
      already_invited_ids = @vacancy.invitations.pluck(:person_id)
      already_cast_ids = @vacancy.show.show_person_role_assignments
                                      .where(assignable_type: "Person")
                                      .pluck(:assignable_id)
      vacated_by_id = @vacancy.vacated_by_id
      excluded_ids = (already_invited_ids + already_cast_ids + [ vacated_by_id ].compact).uniq

      # Determine which people to invite based on mode
      person_ids = case invite_mode
      when "all"
        # All talent pool members (not restricted role)
        @production.effective_talent_pool.people
              .where.not(id: excluded_ids)
              .pluck(:id)
      else
        # "specific" mode or restricted role - use member_ids from form
        # Parse member_ids which are in format "Person_123" or "Group_456"
        member_ids = params[:member_ids] || []
        person_ids_from_form = []
        group_ids = []

        member_ids.each do |member_id|
          type, id = member_id.split("_", 2)
          if type == "Person"
            person_ids_from_form << id.to_i
          elsif type == "Group"
            group_ids << id.to_i
          end
        end

        # Expand groups into their members (only those with notifications enabled)
        if group_ids.any?
          group_member_ids = GroupMembership.where(group_id: group_ids)
                                            .includes(:person)
                                            .select(&:notifications_enabled?)
                                            .map(&:person_id)
          person_ids_from_form.concat(group_member_ids)
        end

        # Filter out excluded IDs and deduplicate
        person_ids_from_form.uniq - excluded_ids
      end

      if person_ids.empty?
        redirect_to manage_casting_vacancy_path(@production, @vacancy),
                    alert: "Please select at least one cast member to invite."
        return
      end

      # Get eligible people for invitations (to count for batch)
      eligible_people = Person.where(id: person_ids).select do |person|
        @vacancy.can_invite?(person) && (person.user.nil? || person.user.notification_enabled?(:vacancy_invitations))
      end

      # Create email batch if sending to multiple recipients
      email_batch = nil
      if eligible_people.size > 1
        email_batch = EmailBatch.create!(
          user: Current.user,
          subject: email_subject || "You're invited to fill a role in #{@production.name}",
          recipient_count: eligible_people.size,
          sent_at: Time.current
        )
      end

      invited_count = 0

      Person.where(id: person_ids).find_each do |person|
        next unless @vacancy.can_invite?(person)

        invitation = @vacancy.invitations.create!(
          person: person,
          email_subject: email_subject,
          email_body: email_body
        )

        # Send the invitation email if user has notifications enabled
        if person.user.nil? || person.user.notification_enabled?(:vacancy_invitations)
          VacancyInvitationMailer.invitation_email(invitation, email_batch_id: email_batch&.id).deliver_later
        end
        invited_count += 1
      end

      # Mark the vacancy as finding replacement if we sent any invitations
      @vacancy.mark_finding_replacement! if invited_count > 0

      redirect_to manage_casting_vacancy_path(@production, @vacancy),
                  notice: "Invited #{invited_count} #{'person'.pluralize(invited_count)}."
    end

    def cancel
      @vacancy.mark_not_filling!(by: Current.user)
      redirect_to manage_production_path(@production),
                  notice: "Vacancy closed without filling."
    end

    def fill
      person_id = params[:person_id]
      person = Person.find(person_id)

      # The fill! method handles removing old assignment, creating new assignment, and updating vacancy status
      @vacancy.fill!(person, by: Current.person)

      redirect_to manage_production_path(@production),
                  notice: "Vacancy filled by #{person.name}."
    end

    private

    def set_production
      unless Current.organization
        redirect_to select_organization_path, alert: "Please select an organization first."
        return
      end
      @production = Current.organization.productions.find(params[:production_id])
      sync_current_production(@production)
    end

    def set_vacancy
      @vacancy = RoleVacancy.joins(:show)
                            .includes(:role)
                            .where(shows: { production_id: @production.id })
                            .find(params[:id])
    end

    def default_vacancy_email_subject
      template_vars = vacancy_email_template_vars
      if linked_vacancy?
        EmailTemplateService.render_subject_without_prefix("vacancy_invitation_linked", template_vars)
      else
        EmailTemplateService.render_subject_without_prefix("vacancy_invitation", template_vars)
      end
    end

    def default_vacancy_email_body
      template_vars = vacancy_email_template_vars
      if linked_vacancy?
        EmailTemplateService.render_body("vacancy_invitation_linked", template_vars)
      else
        EmailTemplateService.render_body("vacancy_invitation", template_vars)
      end
    end

    def linked_vacancy?
      @vacancy.show.linked? && @vacancy.show.event_linkage.shows.count > 1
    end

    def vacancy_email_template_vars
      show = @vacancy.show
      if linked_vacancy?
        all_shows_list = show.event_linkage.shows.order(:date_and_time).to_a
        shows_text = all_shows_list.map do |s|
          event_name = s.secondary_name.presence || s.event_type.titleize
          "#{s.date_and_time.strftime("%A, %B %d at %l:%M %p").strip} - #{event_name}"
        end.join("<br>")
        {
          production_name: @production.name,
          role_name: @vacancy.role.name,
          show_count: all_shows_list.size.to_s,
          shows_list: shows_text
        }
      else
        event_name = show.secondary_name.presence || show.event_type.titleize
        shows_text = "#{show.date_and_time.strftime("%A, %B %d at %l:%M %p")} - #{event_name}"
        {
          production_name: @production.name,
          role_name: @vacancy.role.name,
          event_name: event_name,
          show_date: show.date_and_time.strftime("%b %-d"),
          show_info: shows_text
        }
      end
    end
  end
end

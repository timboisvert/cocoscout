# frozen_string_literal: true

# The notices around a shift vacancy (VacancyNotificationService's job, for
# staff): the chosen managers (Staffing → Settings → Notifications) hear that
# someone can't make a shift, that it's covered, and that they can make it
# after all; whoever dropped it hears who's covering it. Every one is a
# seeded ContentTemplate, delivered as an automated notice with no person
# attributed, by message (a Notification in the Shifts group) and by email.
class ShiftVacancyNotificationService
  class << self
    def notify_created(assignment)
      shift = assignment.shift
      organization = shift.organization
      recipients = organization.staffing_notification_recipients
      return if recipients.empty?

      vacancy = assignment.active_vacancy
      deliver("shift_declined_manager", recipients, organization, for_managers: true,
              variables: shift_variables(shift).merge(
                person_name: assignment.person.name,
                decline_reason: assignment.decline_reason.presence,
                vacancy_url: (vacancy_url(vacancy) if vacancy),
                scheduling_url: scheduling_url(shift)
              ))
    end

    # Claimed by the person themself: they're covering it. Put on by a manager
    # (fill! with accepted: false, fill_from_assignment!): they haven't said
    # yes, so the words say "put on", not "covering", and say whether they've
    # heard: told at once when a manager picked them by hand
    # (StaffScheduleNotices.tell_new_shift!), otherwise with the week's next
    # updates, and never "will be told" of someone with no login. The one who
    # dropped it reads "you", not their own name.
    def notify_filled(vacancy)
      shift = vacancy.shift
      organization = shift.organization
      filled_by = vacancy.filled_by
      row = shift.shift_assignments.find_by(person_id: filled_by&.id)
      claimed = row&.accepted_at.present?
      variables = shift_variables(shift).merge(person_name: vacancy.vacated_by.name, filled_by_name: filled_by&.name.to_s)
      role = variables[:role_name]
      subject = claimed ? "#{filled_by&.name} is covering the #{role} shift on #{variables[:shift_date]}" :
                          "#{filled_by&.name} has been put on the #{role} shift on #{variables[:shift_date]}"
      told = if row&.notified_at.present? then ", and has been told"
      elsif filled_by&.user.nil? then ""
      else ", and will be told"
      end
      words = ->(dropper) do
        who = dropper ? "you" : vacancy.vacated_by.name
        claimed ? "#{filled_by&.name} is covering the <strong>#{role}</strong> shift on <strong>#{variables[:shift_time]}</strong> that #{who} couldn't make." :
                  "#{filled_by&.name} has been put on the <strong>#{role}</strong> shift on <strong>#{variables[:shift_time]}</strong> that #{who} couldn't make#{told}."
      end

      managers = organization.staffing_notification_recipients
      if managers.any?
        deliver("shift_vacancy_filled", managers, organization, for_managers: true,
                variables: variables.merge(covering_subject: subject, covering_words: words.call(false), link_url: vacancy_url(vacancy), link_text: "See the shift"))
      end
      deliver("shift_vacancy_filled", [ vacancy.vacated_by ], organization, for_managers: false,
              variables: variables.merge(covering_subject: subject, covering_words: words.call(true), link_url: my_shifts_url, link_text: "My Shifts"))
    end

    # They claimed it from an invitation: their confirmation, the moment it
    # happens (the claim page said it and nothing else did).
    def notify_claimed(invitation)
      vacancy = invitation.shift_vacancy
      shift = vacancy.shift
      deliver("shift_claim_confirmed", [ invitation.person ], shift.organization, for_managers: false,
              variables: ShiftWords.variables(shift, invitation.person).merge(vacated_by_name: vacancy.vacated_by.name))
    end

    def notify_reclaimed(vacancy)
      shift = vacancy.shift
      organization = shift.organization
      managers = organization.staffing_notification_recipients
      return if managers.empty?

      deliver("shift_vacancy_reclaimed", managers, organization, for_managers: true,
              variables: shift_variables(shift).merge(person_name: vacancy.vacated_by.name, vacancy_url: vacancy_url(vacancy)))
    end

    # The invitation's words (the vacancy page's draft and the mailer): the
    # shift, where, the shows that night, and for one recipient their name
    # and claim link. Without a person, those two tokens stay for the mailer.
    def invitation_variables(vacancy, person: nil, claim_url: nil)
      shift = vacancy.shift
      shows = shift.shows_on_duty.map { |s| "#{s.production&.name} (#{s.date_and_time.strftime("%-l:%M %p")})" }
      location = shift.house_role&.location&.name || shift.source.try(:location).try(:name)
      shift_variables(shift).merge(
        person_name: vacancy.vacated_by.name,
        shift_info: "#{shift.starts_at.strftime("%A, %B %-d")}, #{shift.starts_at.strftime("%-l:%M %p")}–#{shift.ends_at.strftime("%-l:%M %p")}",
        location_name: location.presence,
        shows_list: shows.join(", ").presence,
        recipient_name: person&.name&.split&.first,
        claim_url: claim_url
      ).compact
    end

    private

    def deliver(template_key, recipients, organization, variables:, for_managers:)
      ContentTemplateService.deliver(
        template_key: template_key,
        variables: variables.compact,
        sender: nil,
        recipients: recipients,
        organization: organization,
        message_type: :system,
        # A notice for managers must reach the manage inbox, which
        # system_generated would hide it from; a staffer's is the usual
        # automated notice. :system keeps the attribution automated either way.
        system_generated: !for_managers,
        mailer_class: StaffingNoticeMailer.with(organization_id: organization.id),
        mailer_method: :notice
      )
    end

    def shift_variables(shift)
      starts = shift.starts_at
      {
        # The whole label: a Bartender + Door shift isn't a Bartender shift.
        role_name: shift.role_label.presence || "staff",
        shift_date: starts.strftime("%a, %b %-d"),
        shift_time: starts.strftime("%A, %B %-d at %-l:%M %p"),
        organization_name: shift.organization.name
      }
    end

    def vacancy_url(vacancy)
      url_helpers.manage_staffing_vacancy_url(vacancy, **url_options)
    end

    def scheduling_url(shift)
      url_helpers.manage_staffing_scheduling_url(day: shift.starts_at.to_date.iso8601, **url_options)
    end

    def my_shifts_url
      url_helpers.my_shifts_url(**url_options)
    end

    def url_helpers
      Rails.application.routes.url_helpers
    end

    # The mailer's host and port (the links in an email are the mailer's).
    def url_options
      opts = Rails.application.config.action_mailer.default_url_options.presence || { host: "localhost", port: 3000 }
      opts.slice(:host, :port, :protocol)
    end
  end
end

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

    def notify_filled(vacancy)
      shift = vacancy.shift
      organization = shift.organization
      variables = shift_variables(shift).merge(person_name: vacancy.vacated_by.name, filled_by_name: vacancy.filled_by&.name.to_s)

      managers = organization.staffing_notification_recipients
      if managers.any?
        deliver("shift_vacancy_filled", managers, organization, for_managers: true,
                variables: variables.merge(link_url: vacancy_url(vacancy), link_text: "See the shift"))
      end
      deliver("shift_vacancy_filled", [ vacancy.vacated_by ], organization, for_managers: false,
              variables: variables.merge(link_url: my_shifts_url, link_text: "My Shifts"))
    end

    def notify_reclaimed(vacancy)
      shift = vacancy.shift
      organization = shift.organization
      managers = organization.staffing_notification_recipients
      return if managers.empty?

      deliver("shift_vacancy_reclaimed", managers, organization, for_managers: true,
              variables: shift_variables(shift).merge(person_name: vacancy.vacated_by.name, vacancy_url: vacancy_url(vacancy)))
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
        role_name: shift.house_role&.name || "staff",
        shift_date: starts.strftime("%a, %b %-d"),
        shift_time: starts.strftime("%A, %B %-d at %-l:%M %p"),
        organization_name: shift.organization.name
      }
    end

    def vacancy_url(vacancy)
      url_helpers.manage_staffing_vacancy_url(vacancy, host: default_host)
    end

    def scheduling_url(shift)
      url_helpers.manage_staffing_scheduling_url(day: shift.starts_at.to_date.iso8601, host: default_host)
    end

    def my_shifts_url
      url_helpers.my_shifts_url(host: default_host)
    end

    def url_helpers
      Rails.application.routes.url_helpers
    end

    def default_host
      Rails.application.config.action_mailer.default_url_options&.dig(:host) || "localhost:3000"
    end
  end
end

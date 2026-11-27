# frozen_string_literal: true

# Service for sending vacancy-related notifications to producers.
#
# This service handles vacancy creation, filling, and reclaim notifications,
# routing them through the message system or email based on template channel settings.
#
# Usage:
#   VacancyNotificationService.notify_vacancy_created(vacancy)
#   VacancyNotificationService.notify_vacancy_filled(vacancy)
#   VacancyNotificationService.notify_vacancy_reclaimed(vacancy)
#
class VacancyNotificationService
  class << self
    # Notify team when a vacancy is created
    def notify_vacancy_created(vacancy, sender: nil)
      production = vacancy.show&.production
      return empty_result unless production

      recipients = find_notifiable_users(production)

      # For vacancy created by group, also notify group members
      if vacancy.vacated_by.is_a?(Group)
        group_member_users = vacancy.vacated_by.group_memberships
                                    .includes(person: :user)
                                    .select(&:notifications_enabled?)
                                    .map { |gm| gm.person.user }
                                    .compact
        recipients.concat(group_member_users)
      end

      recipients.uniq!
      return empty_result if recipients.empty?

      send_notifications(
        vacancy: vacancy,
        production: production,
        recipients: recipients,
        sender: sender,
        template_key: "vacancy_created",
        extra_variables: {
          person_name: vacancy.vacated_by&.name || "A cast member"
        }
      )
    end

    # Notify team when one person gives up several at once (a performer with
    # several acts in a show, VacancyController#confirm): one notice that
    # names every act, not one notice per act (Tim, 2026-11-24).
    def notify_vacancies_created(vacancies, sender: nil)
      vacancies = Array(vacancies)
      return notify_vacancy_created(vacancies.first, sender: sender) if vacancies.size == 1

      vacancy = vacancies.first
      show = vacancy&.show
      production = show&.production
      return empty_result unless production

      recipients = find_notifiable_users(production)
      vacancies.map(&:vacated_by).uniq.grep(Group).each do |group|
        recipients.concat(group.group_memberships.includes(person: :user).select(&:notifications_enabled?).filter_map { |gm| gm.person.user })
      end
      recipients.uniq!
      return empty_result if recipients.empty?

      numbers = show.act_based? ? Role.lineup_numbers_for(show.available_roles.to_a) : {}
      roles = vacancies.map(&:role).sort_by { |role| [ numbers[role.id] || 0, role.position || 0 ] }
      unit = roles.all? { |role| role.act?(show: show) } ? "act" : "assignment"

      send_notifications(
        vacancy: vacancy,
        production: production,
        recipients: recipients,
        sender: sender,
        # VacancyTemplates::SEVERAL, spelled out: communications:validate
        # reads this file for the key in quotes, as it finds the other three.
        template_key: "vacancy_created_several",
        extra_variables: {
          person_name: vacancies.filter_map { |v| v.vacated_by&.name }.uniq.to_sentence.presence || "A cast member",
          how_many: "#{roles.size} #{unit.pluralize(roles.size)}",
          names: roles.map { |role| role.display_name(number: numbers[role.id], show: show) }.to_sentence
        }
      )
    end

    # Notify team when a vacancy is filled
    def notify_vacancy_filled(vacancy, sender: nil)
      production = vacancy.show&.production
      return empty_result unless production

      recipients = find_notifiable_users(production)
      return empty_result if recipients.empty?

      send_notifications(
        vacancy: vacancy,
        production: production,
        recipients: recipients,
        sender: sender,
        template_key: "vacancy_filled",
        extra_variables: {
          person_name: vacancy.vacated_by&.name || "The original cast member",
          filled_by_name: vacancy.filled_by&.name || "Someone"
        }
      )
    end

    # Notify team when a vacancy is reclaimed
    def notify_vacancy_reclaimed(vacancy, sender: nil)
      production = vacancy.show&.production
      return empty_result unless production

      recipients = find_notifiable_users(production)
      return empty_result if recipients.empty?

      send_notifications(
        vacancy: vacancy,
        production: production,
        recipients: recipients,
        sender: sender,
        template_key: "vacancy_reclaimed",
        extra_variables: {
          person_name: vacancy.vacated_by&.name || "The cast member"
        }
      )
    end

    # Legacy method for backwards compatibility
    def notify_team(vacancy, event, sender: nil)
      case event
      when "created" then notify_vacancy_created(vacancy, sender: sender)
      when "filled" then notify_vacancy_filled(vacancy, sender: sender)
      when "reclaimed" then notify_vacancy_reclaimed(vacancy, sender: sender)
      else empty_result
      end
    end

    private

    def empty_result
      { messages_sent: 0, emails_sent: 0 }
    end

    def send_notifications(vacancy:, production:, recipients:, sender:, template_key:, extra_variables:)
      result = empty_result

      channel = ContentTemplateService.channel_for(template_key) || :both
      show = vacancy.show
      role = vacancy.role

      base_variables = {
        role_name: role.name,
        show_date: show.date_and_time.strftime("%B %-d at %-I:%M %p"),
        production_name: production.name,
        show_url: Rails.application.routes.url_helpers.manage_casting_show_cast_url(
          production_id: production.id,
          show_id: show.id,
          host: default_host
        ),
        vacancy_url: Rails.application.routes.url_helpers.manage_casting_vacancy_url(
          production_id: production.id,
          id: vacancy.id,
          host: default_host
        )
      }.merge(extra_variables)

      recipients.each do |user|
        next unless user&.email_address.present?

        person = user.person
        variables = base_variables.merge(
          recipient_name: person&.name&.split&.first || user.email_address.split("@").first
        )

        rendered = ContentTemplateService.render(template_key, variables)

        # Send as in-app message (system_generated: true so it doesn't appear in sender's sent folder)
        if channel == :message || channel == :both
          if person.present?
            message = MessageService.send_direct(
              template_key: template_key, push_body: rendered[:push_body],
              sender: sender || system_sender(production),
              recipient_person: person,
              subject: rendered[:subject],
              body: rendered[:body],
              production: production,
              organization: production.organization,
              system_generated: true
            )
            result[:messages_sent] += 1 if message
          end
        end

        # Send as email
        if channel == :email || channel == :both
          # A notification now, with no email (NotificationGroups.email?).
          should_email = NotificationGroups.email?(template_key, user) && user.notification_enabled?(:vacancy_notifications)
          if should_email
            begin
              VacancyNotificationMailer.with(
                user: user,
                subject: rendered[:subject],
                body: rendered[:body],
                vacancy: vacancy
              ).vacancy_notification.deliver_later
              result[:emails_sent] += 1
            rescue StandardError => e
              Rails.logger.error "VacancyNotificationService: Failed to send email to #{user.email_address}: #{e.message}"
            end
          end
        end
      end

      result
    end

    def find_notifiable_users(production)
      ProductionNotificationSetting.users_to_notify(production)
    end

    def system_sender(_production)
      nil  # System vacancy messages have no personal sender — show production name instead
    end

    def default_host
      Rails.application.config.action_mailer.default_url_options&.dig(:host) || "localhost:3000"
    end
  end
end

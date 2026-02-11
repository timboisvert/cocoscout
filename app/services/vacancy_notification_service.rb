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
        show_url: Rails.application.routes.url_helpers.manage_casting_show_url(
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
          should_email = user.notification_enabled?(:vacancy_notifications)
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
      organization = production.organization
      users_with_production_permission_ids = production.production_permissions.pluck(:user_id)

      # Get users with explicit production permissions who have notifications enabled
      users_with_permissions = production.production_permissions
                                         .includes(:user)
                                         .select(&:notifications_enabled?)
                                         .map(&:user)

      # Get the organization owner if they don't have an explicit production permission
      owner = organization.owner
      owner_without_explicit_permission = if owner && !users_with_production_permission_ids.include?(owner.id)
        owner_org_role = organization.organization_roles.find_by(user: owner)
        if owner_org_role.nil? || owner_org_role.notifications_enabled?
          [ owner ]
        else
          []
        end
      else
        []
      end

      # Get users with global manager role who don't have a production permission
      users_with_global_manager = organization.organization_roles
                                              .where(company_role: "manager")
                                              .where.not(user_id: users_with_production_permission_ids)
                                              .select(&:notifications_enabled?)
                                              .map(&:user)

      (users_with_permissions + owner_without_explicit_permission + users_with_global_manager).compact.uniq
    end

    def system_sender(production)
      production.organization.owner
    end

    def default_host
      Rails.application.config.action_mailer.default_url_options&.dig(:host) || "localhost:3000"
    end
  end
end

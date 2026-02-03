# frozen_string_literal: true

# Service for sending sign-up registration notifications to production team members.
# This respects the ContentTemplate channel setting (email, message, or both).
#
# Usage:
#   SignUpProducerNotificationService.notify_team(registration)
#
class SignUpProducerNotificationService
  TEMPLATE_KEY = "sign_up_registration_notification"

  class << self
    # Notify team members about a new sign-up registration
    #
    # @param registration [SignUpRegistration] The registration that was submitted
    # @param sender [User, nil] Optional sender user for messages
    def notify_team(registration, sender: nil)
      slot = registration.sign_up_slot
      return unless slot

      form = slot.sign_up_form
      return unless form&.notify_on_registration?

      production = form.production
      return unless production

      # Find all team members with notifications enabled
      recipients = find_notifiable_users(production)
      return if recipients.empty?

      # Determine channel from template
      channel = ContentTemplateService.channel_for(TEMPLATE_KEY)

      # Build base template variables (recipient_name added per-recipient)
      base_variables = build_template_variables(registration, slot, form, production)

      # Find sender for messages
      sender ||= find_sender(production)

      recipients.each do |user|
        # Add recipient-specific variables
        variables = base_variables.merge(
          recipient_name: user.person&.name&.split&.first || user.email_address&.split("@")&.first || "Team Member"
        )

        # Render template for this recipient
        rendered = ContentTemplateService.render(TEMPLATE_KEY, variables)
        subject = rendered[:subject]
        body = rendered[:body]

        # Send message if channel is :message or :both
        if channel.in?([ :message, :both ]) && sender && user.person
          MessageService.send_direct(
            sender: sender,
            recipient_person: user.person,
            subject: subject,
            body: body,
            production: production,
            organization: production.organization
          )
        end

        # Send email if channel is :email or :both
        if channel.in?([ :email, :both ])
          Manage::SignUpMailer.with(
            user: user,
            registration: registration,
            subject: subject,
            body: body
          ).registration_notification.deliver_later
        end
      end
    end

    private

    def build_template_variables(registration, slot, form, production)
      instance = slot.sign_up_form_instance
      show = instance&.show
      registrant_name = registration.person&.name || registration.guest_name || "Guest"
      show_name = show&.secondary_name.presence || show&.event_type&.titleize || instance&.show_name || "Event"
      show_date = show&.date_and_time&.strftime("%B %d, %Y at %l:%M %p") || instance&.show_date&.strftime("%B %d, %Y") || "TBD"

      {
        registrant_name: registrant_name,
        sign_up_form_name: form.name,
        slot_name: slot.display_name,
        show_name: show_name,
        show_date: show_date,
        production_name: production.name,
        event_info: "#{show_name} on #{show_date}",
        registrations_url: Rails.application.routes.url_helpers.manage_sign_up_form_registrations_url(
          production_id: production.id,
          sign_up_form_id: form.id,
          host: default_host
        )
      }
    end

    def find_notifiable_users(production)
      organization = production.organization
      users_with_production_permission_ids = production.production_permissions.pluck(:user_id)

      # Get team members who have explicit production permissions with notifications enabled
      users_with_permissions = production.production_permissions
                                         .includes(:user)
                                         .select(&:notifications_enabled?)
                                         .map(&:user)

      # Get users with global manager/viewer role who don't have a production permission
      # and have notifications enabled on their organization role (nil = enabled)
      users_with_global_role = organization.organization_roles
                                           .where(company_role: %w[manager viewer])
                                           .where(notifications_enabled: [ true, nil ])
                                           .includes(:user)
                                           .map(&:user)

      # Filter global role users to those without explicit production permissions
      users_with_global_role_only = users_with_global_role.reject do |user|
        users_with_production_permission_ids.include?(user.id)
      end

      (users_with_permissions + users_with_global_role_only).compact.uniq
    end

    def find_sender(production)
      # Use production owner or first manager as sender
      production.organization.owner ||
        production.production_permissions.includes(:user).find_by(role: "manager")&.user
    end

    def default_host
      Rails.application.config.action_mailer.default_url_options&.dig(:host) || "localhost:3000"
    end
  end
end

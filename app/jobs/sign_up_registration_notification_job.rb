# frozen_string_literal: true

class SignUpRegistrationNotificationJob < ApplicationJob
  queue_as :default

  # Notify production team when someone submits a sign-up registration
  # @param sign_up_registration_id [Integer] The ID of the SignUpRegistration
  def perform(sign_up_registration_id)
    registration = SignUpRegistration.find_by(id: sign_up_registration_id)
    return unless registration

    slot = registration.sign_up_slot
    return unless slot

    form = slot.sign_up_form
    return unless form&.notify_on_registration?

    production = form.production
    return unless production

    # Find all team members with notifications enabled for this production
    recipients = find_notifiable_producers(production)
    return if recipients.empty?

    # Send notification to each recipient
    recipients.each do |user|
      Manage::SignUpMailer.registration_notification(user, registration).deliver_later
    end
  end

  private

  def find_notifiable_producers(production)
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
                                         .where(notifications_enabled: [true, nil])
                                         .includes(:user)
                                         .map(&:user)

    # Filter global role users to those without explicit production permissions
    users_with_global_role_only = users_with_global_role.reject do |user|
      users_with_production_permission_ids.include?(user.id)
    end

    (users_with_permissions + users_with_global_role_only).compact.uniq
  end
end

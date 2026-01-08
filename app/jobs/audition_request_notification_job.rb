# frozen_string_literal: true

class AuditionRequestNotificationJob < ApplicationJob
  queue_as :default

  # Notify producers when someone submits an audition request
  # @param audition_request_id [Integer] The ID of the AuditionRequest
  def perform(audition_request_id)
    audition_request = AuditionRequest.find_by(id: audition_request_id)
    return unless audition_request

    audition_cycle = audition_request.audition_cycle
    return unless audition_cycle

    production = audition_cycle.production
    return unless production

    # Find all team members (producers) with notifications enabled for this production
    recipients = find_notifiable_producers(production)
    return if recipients.empty?

    # Send notification to each recipient
    recipients.each do |user|
      Manage::AuditionMailer.audition_request_notification(user, audition_request).deliver_later
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
                                         .where(notifications_enabled: [ true, nil ])
                                         .includes(:user)
                                         .map(&:user)

    # Filter global role users to those without explicit production permissions
    users_with_global_role_only = users_with_global_role.reject do |user|
      users_with_production_permission_ids.include?(user.id)
    end

    (users_with_permissions + users_with_global_role_only).compact.uniq
  end
end

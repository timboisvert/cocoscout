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
    # Get team members who are producers for this production
    production.production_permissions
              .includes(:user)
              .select(&:notifications_enabled?)
              .map(&:user)
              .compact
              .uniq
  end
end

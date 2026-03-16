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

    # Check if notifications are enabled for this audition cycle
    return unless audition_cycle.notify_on_submission?

    production = audition_cycle.production
    return unless production

    # Find all team members (producers) with notifications enabled for this production
    recipients = find_notifiable_producers(production)
    return if recipients.empty?

    # Send notification to each recipient
    recipients.each do |user|
      next unless user.person.present?

      rendered = ContentTemplateService.render("audition_request_submitted", {
        recipient_name: user.person.first_name || "there",
        requestable_name: audition_request.person&.name || "An applicant",
        production_name: production.name,
        review_url: Rails.application.routes.url_helpers.manage_auditions_url(
          production_id: production.id,
          host: ENV.fetch("HOST", "localhost:3000")
        )
      })

      MessageService.send_direct(
        sender: nil,
        recipient_person: user.person,
        subject: rendered[:subject],
        body: rendered[:body],
        production: production,
        organization: production.organization
      )
    end
  end

  private

  def find_notifiable_producers(production)
    ProductionNotificationSetting.ensure_settings_for(production)
    ProductionNotificationSetting.where(production: production, enabled: true)
                                 .includes(:user)
                                 .map(&:user)
                                 .compact
  end
end

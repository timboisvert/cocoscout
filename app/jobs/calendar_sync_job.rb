# frozen_string_literal: true

class CalendarSyncJob < ApplicationJob
  queue_as :default

  def perform(subscription_id)
    subscription = CalendarSubscription.find_by(id: subscription_id)
    return unless subscription&.enabled?

    service = case subscription.provider
    when "google"
                CalendarSync::GoogleService.new(subscription)
    when "outlook"
                CalendarSync::OutlookService.new(subscription)
    when "ical"
                CalendarSync::IcalService.new(subscription)
    else
                Rails.logger.error("Unknown calendar provider: #{subscription.provider}")
                return
    end

    service.sync_all
  rescue StandardError => e
    Rails.logger.error("CalendarSyncJob failed for subscription #{subscription_id}: #{e.message}")
    subscription&.mark_sync_error!(e.message)
  end
end

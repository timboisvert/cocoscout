# frozen_string_literal: true

# Daily: ticket money for shows that happened before today becomes the
# theater's to spend (see TicketMoneyRelease).
class TicketMoneyReleaseJob < ApplicationJob
  queue_as :default

  def perform
    TicketMoneyRelease.due.find_each do |listing|
      TicketMoneyRelease.release!(listing)
    rescue StandardError => e
      Rails.logger.error("[TicketMoneyReleaseJob] listing #{listing.id}: #{e.class}: #{e.message}")
    end
  end
end

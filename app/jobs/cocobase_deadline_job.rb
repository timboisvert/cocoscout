# frozen_string_literal: true

class CocobaseDeadlineJob < ApplicationJob
  queue_as :default

  # Runs periodically (configured in recurring.yml).
  # Auto-closes cocobases whose deadline has passed.
  def perform
    closed_count = 0

    Cocobase.where(status: :open)
            .where("deadline < ?", Time.current)
            .find_each do |cocobase|
      cocobase.update!(status: :closed)
      closed_count += 1
      Rails.logger.info "[CocobaseDeadlineJob] Auto-closed cocobase #{cocobase.id} for show #{cocobase.show_id}"
    end

    Rails.logger.info "[CocobaseDeadlineJob] Closed #{closed_count} cocobases" if closed_count > 0
  end
end

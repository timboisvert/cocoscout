# frozen_string_literal: true

class WebhookProcessingJob < ApplicationJob
  queue_as :default

  def perform(webhook_log_id)
    webhook_log = WebhookLog.find_by(id: webhook_log_id)
    return unless webhook_log
    return if webhook_log.status_processed? || webhook_log.status_duplicate?

    webhook_log.process!
  end
end

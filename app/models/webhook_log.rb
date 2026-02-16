# frozen_string_literal: true

class WebhookLog < ApplicationRecord
  belongs_to :ticketing_provider
  belongs_to :ticket_listing, optional: true

  enum :status, {
    received: "received",
    processing: "processing",
    processed: "processed",
    failed: "failed",
    ignored: "ignored",
    duplicate: "duplicate"
  }, default: :received, prefix: true

  enum :signature_status, {
    not_checked: "not_checked",
    valid: "valid",
    invalid: "invalid",
    missing: "missing"
  }, default: :not_checked, prefix: :signature

  validates :event_type, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :unprocessed, -> { where(status: %w[received processing]) }
  scope :failed, -> { status_failed }

  # ============================================
  # Lifecycle
  # ============================================

  def mark_processing!
    update!(status: :processing)
  end

  def mark_processed!
    update!(
      status: :processed,
      processed_at: Time.current
    )
  end

  def mark_failed!(error)
    update!(
      status: :failed,
      processing_error: error,
      processed_at: Time.current
    )
  end

  def mark_ignored!(reason = nil)
    update!(
      status: :ignored,
      processing_error: reason,
      processed_at: Time.current
    )
  end

  def mark_duplicate!
    update!(
      status: :duplicate,
      processed_at: Time.current
    )
  end

  # ============================================
  # Helpers
  # ============================================

  def provider_type
    ticketing_provider.provider_type
  end

  def parsed_payload
    payload.is_a?(Hash) ? payload.with_indifferent_access : JSON.parse(payload).with_indifferent_access
  rescue JSON::ParserError
    {}
  end

  # Get a specific field from the payload using dot notation
  # e.g., get_payload_field("order.id")
  def get_payload_field(path)
    path.split(".").reduce(parsed_payload) { |obj, key| obj.try(:[], key) }
  end

  # ============================================
  # Processing
  # ============================================

  def process!
    return if status_processed? || status_duplicate?

    mark_processing!

    begin
      handler = webhook_handler
      result = handler.process(self)

      if result[:success]
        mark_processed!
      elsif result[:duplicate]
        mark_duplicate!
      elsif result[:ignored]
        mark_ignored!(result[:reason])
      else
        mark_failed!(result[:error])
      end

      result
    rescue StandardError => e
      mark_failed!(e.message)
      { success: false, error: e.message }
    end
  end

  def process_async!
    WebhookProcessingJob.perform_later(id)
  end

  private

  def webhook_handler
    case ticketing_provider.provider_type
    when "eventbrite"
      TicketingWebhooks::EventbriteHandler.new(ticketing_provider)
    when "ticket_tailor"
      TicketingWebhooks::TicketTailorHandler.new(ticketing_provider)
    else
      TicketingWebhooks::BaseHandler.new(ticketing_provider)
    end
  end
end

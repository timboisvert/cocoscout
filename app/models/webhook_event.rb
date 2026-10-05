# frozen_string_literal: true

# One row per webhook event we've accepted. Stripe redelivers anything we don't
# answer 2xx, and our handlers move money — so the first delivery claims the
# event and any redelivery is a no-op, unless the handler failed: then the
# claim is marked failed, we answer 500, and Stripe's next delivery gets to
# try again. A claim stuck in processing (the process died mid-handler) can be
# taken over after STALE_AFTER.
class WebhookEvent < ApplicationRecord
  STATUSES = %w[processing processed failed].freeze
  STALE_AFTER = 10.minutes

  validates :provider, :event_id, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :failed, -> { where(status: "failed") }

  # True if this delivery is the one that gets to do the work. The unique index
  # on (provider, event_id) decides a first delivery; a conditional update
  # decides a retry, so two concurrent deliveries can't both win.
  def self.claim!(provider:, event_id:, event_type: nil)
    return true if event_id.blank? # nothing to key on; don't drop the event

    create!(provider: provider, event_id: event_id, event_type: event_type, status: "processing", updated_at: Time.current)
    true
  rescue ActiveRecord::RecordNotUnique
    now = Time.current
    where(provider: provider, event_id: event_id)
      .where("status = 'failed' OR (status = 'processing' AND updated_at < ?)", now - STALE_AFTER)
      .update_all([ "status = 'processing', attempts = attempts + 1, updated_at = ?", now ]) == 1
  end

  def self.finish!(provider:, event_id:)
    return if event_id.blank?

    now = Time.current
    where(provider: provider, event_id: event_id).update_all(status: "processed", processed_at: now, error: nil, updated_at: now)
  end

  def self.fail!(provider:, event_id:, error:)
    return if event_id.blank?

    where(provider: provider, event_id: event_id)
      .update_all(status: "failed", error: "#{error.class}: #{error.message}".truncate(2_000), updated_at: Time.current)
  end
end

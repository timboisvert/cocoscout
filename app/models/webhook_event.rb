# frozen_string_literal: true

# One row per webhook event we've accepted. Stripe redelivers anything we don't
# answer 2xx, and our handlers move money — so the first delivery claims the
# event and any redelivery is a no-op.
class WebhookEvent < ApplicationRecord
  validates :provider, :event_id, presence: true

  # True if this delivery is the one that gets to do the work. The unique index
  # on (provider, event_id) is what actually decides it, so two concurrent
  # deliveries can't both win.
  def self.claim!(provider:, event_id:, event_type: nil)
    return true if event_id.blank? # nothing to key on; don't drop the event

    create!(provider: provider, event_id: event_id, event_type: event_type)
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end
end

# frozen_string_literal: true

class TicketingPendingEvent < ApplicationRecord
  belongs_to :ticketing_provider
  belongs_to :suggested_production, class_name: "Production", optional: true
  belongs_to :matched_production_link, class_name: "TicketingProductionLink", optional: true
  belongs_to :dismissed_by, class_name: "User", optional: true

  # Statuses
  STATUSES = %w[pending matched dismissed].freeze

  validates :provider_event_id, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :provider_event_id, uniqueness: { scope: :ticketing_provider_id }

  # Scopes
  scope :pending, -> { where(status: "pending") }
  scope :needs_attention, -> { pending.where(suggested_production_id: nil) }
  scope :has_suggestion, -> { pending.where.not(suggested_production_id: nil) }
  scope :recent, -> { order(created_at: :desc) }

  # Check if this event needs user attention
  def needs_attention?
    status == "pending" && (suggested_production_id.nil? || match_confidence.to_f < 0.8)
  end

  # Mark as matched and create the production link
  def match_to_production!(production, user: nil)
    transaction do
      link = ticketing_provider.ticketing_production_links.create!(
        production: production,
        provider_event_id: provider_event_id,
        provider_event_name: provider_event_name,
        sync_enabled: true,
        sync_ticket_sales: true
      )

      update!(
        status: "matched",
        matched_production_link: link,
        suggested_production: production
      )

      link
    end
  end

  # Dismiss this event (won't show up in pending list)
  def dismiss!(user)
    update!(
      status: "dismissed",
      dismissed_at: Time.current,
      dismissed_by: user
    )
  end

  # Delegate to provider for display
  delegate :organization, to: :ticketing_provider
end

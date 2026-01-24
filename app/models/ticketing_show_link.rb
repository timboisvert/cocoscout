# frozen_string_literal: true

class TicketingShowLink < ApplicationRecord
  belongs_to :show
  belongs_to :ticketing_production_link

  has_one :ticketing_provider, through: :ticketing_production_link
  has_one :production, through: :ticketing_production_link

  # Sync statuses
  SYNC_STATUSES = %w[pending synced error].freeze

  # Validations
  validates :show_id, uniqueness: {
    scope: :ticketing_production_link_id,
    message: "is already linked to this ticketing event"
  }
  validates :sync_status, inclusion: { in: SYNC_STATUSES }, allow_nil: true

  # Scopes
  scope :synced, -> { where(sync_status: "synced") }
  scope :pending, -> { where(sync_status: "pending") }
  scope :with_errors, -> { where(sync_status: "error") }
  scope :needs_sync, -> { where("last_synced_at IS NULL OR last_synced_at < ?", 15.minutes.ago) }

  # Callbacks
  after_save :update_show_financials, if: :ticket_data_changed?

  # Check if ticket data changed
  def ticket_data_changed?
    saved_change_to_tickets_sold? ||
      saved_change_to_gross_revenue? ||
      saved_change_to_net_revenue? ||
      saved_change_to_ticket_breakdown?
  end

  # Update the associated ShowFinancials with synced data
  def update_show_financials
    financials = show.show_financials || show.create_show_financials

    financials.update!(
      ticket_count: tickets_sold,
      ticket_revenue: net_revenue || gross_revenue,
      ticket_fees: build_ticket_fees
    )
  end

  # Convert provider fee breakdown into ShowFinancials.ticket_fees format
  def build_ticket_fees
    return [] if ticket_breakdown.blank?

    ticket_breakdown.filter_map do |tier|
      next if tier["fees"].to_f.zero?

      {
        "name" => tier["name"] || "Platform Fee",
        "flat" => tier["fee_per_ticket"].to_f,
        "pct" => tier["fee_percentage"].to_f,
        "amount" => tier["fees"].to_f
      }
    end
  end

  # Get the public ticket page URL
  def ticket_page_url
    provider_ticket_page_url.presence ||
      ticketing_provider&.service&.ticket_page_url_for(self)
  end

  # Mark as synced
  def mark_synced!
    update!(
      sync_status: "synced",
      last_synced_at: Time.current,
      sync_notes: nil
    )
  end

  # Mark as error
  def mark_error!(message)
    update!(
      sync_status: "error",
      sync_notes: message.to_s.truncate(500)
    )
  end

  # Calculate total fees from breakdown
  def total_fees
    return 0 if ticket_breakdown.blank?

    ticket_breakdown.sum { |tier| tier["fees"].to_f }
  end

  # Revenue after fees
  def revenue_after_fees
    (gross_revenue || 0) - total_fees
  end
end

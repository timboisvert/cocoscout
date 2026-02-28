# frozen_string_literal: true

# RemoteTicketingEvent represents an event that ACTUALLY EXISTS on a
# ticketing provider's platform. This is a cache/record of what's been
# created externally, not intent of what SHOULD exist.
#
# This model serves several purposes:
# 1. Track what we've created on each provider
# 2. Cache sales/metrics data pulled from providers
# 3. Identify orphaned events (exist but shouldn't based on current rules)
# 4. Identify missing events (should exist but don't)
# 5. Detect events that need updates
class RemoteTicketingEvent < ApplicationRecord
  belongs_to :ticketing_provider
  belongs_to :provider_event
  belongs_to :production_ticketing_setup, optional: true
  belongs_to :show, optional: true # Null for grouped "parent" events
  belongs_to :organization
  belongs_to :suggested_show, class_name: "Show", optional: true

  # ============================================
  # Enums
  # ============================================

  enum :sync_status, {
    synced: "synced",
    pending_update: "pending_update",
    pending_delete: "pending_delete",
    orphaned: "orphaned",
    error: "error"
  }, prefix: true

  enum :remote_status, {
    draft: "draft",
    live: "live",
    published: "published",
    sales_closed: "sales_closed",
    canceled: "canceled",
    sold_out: "sold_out"
  }, prefix: :remote, default: :draft

  # ============================================
  # Validations
  # ============================================

  validates :external_event_id, presence: true
  validates :external_event_id, uniqueness: { scope: :ticketing_provider_id }

  # ============================================
  # Scopes
  # ============================================

  scope :for_provider, ->(provider) { where(ticketing_provider: provider) }
  scope :for_show, ->(show) { where(show: show) }
  scope :for_setup, ->(setup) { where(production_ticketing_setup: setup) }
  scope :with_shows, -> { where.not(show_id: nil) }
  scope :parent_events, -> { where(show_id: nil) } # For grouped/recurring events
  scope :needs_attention, -> { where(sync_status: %w[pending_update pending_delete orphaned error]) }
  scope :live, -> { where(remote_status: %w[live published]) }
  scope :has_sales, -> { where("tickets_sold > 0") }

  # ============================================
  # Sync Status Management
  # ============================================

  def mark_synced!
    update!(
      sync_status: :synced,
      last_synced_at: Time.current,
      last_sync_error: nil
    )
  end

  def mark_pending_update!
    update!(sync_status: :pending_update)
  end

  def mark_pending_delete!
    update!(sync_status: :pending_delete)
  end

  def mark_orphaned!
    update!(sync_status: :orphaned)
  end

  def mark_error!(error_message)
    update!(
      sync_status: :error,
      last_sync_error: error_message
    )
  end

  # ============================================
  # Data Comparison
  # ============================================

  # Check if the remote event needs to be updated based on new data
  def needs_update?(new_event_data)
    return true if raw_data.blank?

    cached = raw_data.with_indifferent_access

    # Compare key fields
    return true if cached[:name] != new_event_data[:title]
    return true if cached[:description] != new_event_data[:description]

    # Compare times (with tolerance)
    if new_event_data[:start_time].present?
      cached_start = Time.zone.parse(cached[:start_time]) rescue nil
      return true if cached_start.nil? || (cached_start - new_event_data[:start_time]).abs > 60
    end

    false
  end

  # ============================================
  # Sales Data
  # ============================================

  def update_sales_data!(sold:, available:, capacity:, revenue_cents:, currency: "USD")
    update!(
      tickets_sold: sold,
      tickets_available: available,
      capacity: capacity,
      revenue_cents: revenue_cents,
      revenue_currency: currency,
      last_sales_synced_at: Time.current
    )
  end

  def sell_through_percentage
    return 0 if capacity.zero?

    ((tickets_sold.to_f / capacity) * 100).round(1)
  end

  def revenue
    revenue_cents / 100.0
  end

  # ============================================
  # URL Helpers
  # ============================================

  def ticket_url
    external_url
  end

  def provider_manage_url
    case ticketing_provider.provider_type
    when "eventbrite"
      "https://www.eventbrite.com/myevent?eid=#{external_event_id}"
    when "ticket_tailor"
      event_id = external_event_id.split(":").first
      "https://app.tickettailor.com/box-office/events/#{event_id}"
    else
      nil
    end
  end

  # ============================================
  # Sync Operations
  # ============================================

  # Pull latest data from the provider
  def pull_from_provider!
    adapter = ticketing_provider.adapter

    result = adapter.fetch_event(external_event_id)
    return { success: false, error: result[:error] } unless result[:success]

    event_data = result[:data]

    update!(
      remote_status: map_provider_status(event_data[:status]),
      raw_data: event_data,
      external_url: event_data[:url],
      last_synced_at: Time.current
    )

    # Also pull sales data
    pull_sales!

    { success: true }
  rescue StandardError => e
    mark_error!(e.message)
    { success: false, error: e.message }
  end

  # Pull sales data from the provider
  def pull_sales!
    adapter = ticketing_provider.adapter

    result = adapter.fetch_event_sales(external_event_id)
    return unless result[:success]

    update_sales_data!(
      sold: result[:tickets_sold],
      available: result[:tickets_available],
      capacity: result[:capacity],
      revenue_cents: result[:revenue_cents],
      currency: result[:currency] || "USD"
    )
  end

  # Push updates to the provider
  def push_to_provider!
    return { success: false, error: "No setup configured" } unless production_ticketing_setup

    adapter = ticketing_provider.adapter
    event_data = production_ticketing_setup.event_data_for(show)

    result = adapter.update_event(external_event_id, event_data)

    if result[:success]
      mark_synced!
      update!(raw_data: event_data)
      { success: true }
    else
      mark_error!(result[:error])
      { success: false, error: result[:error] }
    end
  end

  # Delete from the provider
  def delete_from_provider!
    adapter = ticketing_provider.adapter

    result = adapter.delete_event(external_event_id)

    if result[:success]
      destroy!
      { success: true }
    else
      mark_error!(result[:error])
      { success: false, error: result[:error] }
    end
  end

  private

  def map_provider_status(status_string)
    case status_string.to_s.downcase
    when "draft" then :remote_draft
    when "live", "published", "on_sale" then :remote_live
    when "sales_closed", "ended" then :remote_sales_closed
    when "canceled", "cancelled" then :remote_canceled
    when "sold_out" then :remote_sold_out
    else :remote_draft
    end
  end
end

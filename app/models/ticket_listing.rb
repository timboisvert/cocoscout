# frozen_string_literal: true

class TicketListing < ApplicationRecord
  belongs_to :show_ticketing
  belongs_to :ticketing_provider

  has_many :ticket_offers, dependent: :destroy
  has_many :ticket_sales, through: :ticket_offers
  has_many :webhook_logs, dependent: :nullify

  # Enhanced status enum with all possible states
  enum :status, {
    pending_data: "pending_data",         # Missing required fields for this provider
    ready: "ready",                       # Has all data, ready to push
    pending_sync: "pending_sync",         # Queued for API push
    syncing: "syncing",                   # Currently being pushed
    pending_approval: "pending_approval", # Pushed, awaiting provider approval
    live: "live",                         # Published and selling
    sync_failed: "sync_failed",           # Push failed (with error details)
    auth_expired: "auth_expired",         # Provider credentials invalid
    paused: "paused",                     # Manually paused
    ended: "ended",                       # Show complete or listing closed
    manual_required: "manual_required",   # Provider has no API, needs human action
    manual_confirmed: "manual_confirmed"  # Human confirmed manual listing complete
  }, default: :pending_data, prefix: true

  validates :show_ticketing_id, uniqueness: { scope: :ticketing_provider_id }

  # Scopes for different listing states
  scope :active, -> { where(status: %w[live paused manual_confirmed]) }
  scope :selling, -> { where(status: %w[live manual_confirmed]) }
  scope :needs_attention, -> { where(status: %w[pending_data sync_failed auth_expired manual_required]) }
  scope :pending, -> { where(status: %w[pending_sync syncing pending_approval]) }
  scope :ready_to_sync, -> { where(status: %w[ready pending_sync]) }
  scope :due_for_sync, -> { where("next_sync_at <= ?", Time.current) }

  accepts_nested_attributes_for :ticket_offers, allow_destroy: true

  before_validation :check_data_completeness, on: :update
  after_create :initialize_status

  # ============================================
  # Status Helpers
  # ============================================

  def healthy?
    status_live? || status_manual_confirmed?
  end

  def needs_attention?
    %w[pending_data sync_failed auth_expired manual_required].include?(status)
  end

  def can_sync?
    return false unless ticketing_provider.can_sync?
    return false if ticketing_provider.manual_only?
    %w[ready pending_sync live].include?(status)
  end

  def manual_provider?
    ticketing_provider.manual_only?
  end

  # ============================================
  # Data Completeness
  # ============================================

  def check_data_completeness
    return if status_ended?

    fields = calculate_missing_fields
    self.missing_fields = fields

    # Auto-transition based on completeness
    if manual_provider?
      self.status = :manual_required if status_pending_data? && fields.empty?
    elsif fields.any?
      self.status = :pending_data unless status_ended?
    elsif status_pending_data?
      self.status = :ready
    end
  end

  def calculate_missing_fields
    missing = []
    show = show_ticketing.show

    # Base requirements
    missing << "show_name" if show.display_name.blank?
    missing << "show_date" if show.date_and_time.blank?
    missing << "ticket_tiers" if show_ticketing.show_ticket_tiers.none?

    # Provider-specific requirements
    adapter = ticketing_provider.adapter
    if adapter.respond_to?(:required_fields)
      adapter.required_fields.each do |field, check|
        missing << field.to_s unless check.call(self)
      end
    end

    missing
  end

  def data_complete?
    missing_fields.empty?
  end

  # ============================================
  # State Transitions
  # ============================================

  # Mark as ready for sync
  def mark_ready!
    return unless data_complete?
    return if manual_provider?
    update!(status: :ready)
  end

  # Queue for sync
  def queue_sync!
    return unless status_ready? || status_live?
    update!(status: :pending_sync, next_sync_at: Time.current)
    TicketListingSyncJob.perform_later(id)
  end

  # Start syncing
  def start_sync!
    update!(
      status: :syncing,
      last_sync_attempt_at: Time.current,
      sync_attempt_count: sync_attempt_count + 1
    )
  end

  # Mark sync successful
  def sync_succeeded!(event_id: nil, event_url: nil, needs_approval: false)
    attrs = {
      last_synced_at: Time.current,
      sync_errors: [],
      sync_attempt_count: 0,
      next_sync_at: calculate_next_sync_time
    }

    if event_id.present?
      attrs[:external_event_id] = event_id
      attrs[:external_url] = event_url
      attrs[:published_at] ||= Time.current
      attrs[:submitted_at] = Time.current
    end

    if needs_approval
      attrs[:status] = :pending_approval
      attrs[:approval_status] = "pending"
    elsif published_at.present? || event_id.present?
      attrs[:status] = :live
    else
      attrs[:status] = :ready
    end

    update!(attrs)
  end

  # Mark sync failed
  def sync_failed!(error, auth_error: false, rate_limited: false)
    add_sync_error(error)

    new_status = if auth_error
      ticketing_provider.mark_credentials_invalid!(error)
      :auth_expired
    elsif rate_limited
      :ready # Will retry after rate limit clears
    else
      :sync_failed
    end

    # Exponential backoff for retries (max 1 hour)
    backoff = [ 2**sync_attempt_count * 30, 3600 ].min.seconds

    update!(
      status: new_status,
      next_sync_at: backoff.from_now
    )
  end

  # Mark approval received
  def mark_approved!
    return unless status_pending_approval?
    update!(
      status: :live,
      approved_at: Time.current,
      approval_status: "approved"
    )
  end

  # Mark approval rejected
  def mark_rejected!(reason = nil)
    return unless status_pending_approval?
    update!(
      status: :sync_failed,
      approval_status: "rejected",
      sync_errors: sync_errors + [ { message: "Approval rejected: #{reason}", at: Time.current.iso8601 } ]
    )
  end

  # Manual workflow
  def mark_manual_complete!(external_url: nil, notes: nil)
    return unless status_manual_required?
    update!(
      status: :manual_confirmed,
      external_url: external_url,
      manual_action_completed_at: Time.current,
      manual_action_notes: notes
    )
  end

  def reset_manual_status!
    return unless status_manual_confirmed?
    update!(
      status: :manual_required,
      manual_action_completed_at: nil
    )
  end

  # Pause/Resume
  def pause!
    return unless status_live? || status_manual_confirmed?
    update!(status: :paused)
  end

  def resume!
    return unless status_paused?
    new_status = manual_provider? ? :manual_confirmed : :live
    update!(status: new_status)
  end

  # End listing
  def end_listing!
    update!(status: :ended)
  end

  # ============================================
  # Sync Operations
  # ============================================

  # Main sync method - handles all the state transitions
  def sync!
    return { success: false, error: "Cannot sync" } unless can_sync?

    start_sync!
    adapter = ticketing_provider.adapter

    begin
      result = if external_event_id.present?
        # Update existing listing
        adapter.update_event(self)
      else
        # Create new listing
        adapter.create_event(self)
      end

      if result[:success]
        sync_succeeded!(
          event_id: result[:event_id],
          event_url: result[:event_url],
          needs_approval: result[:needs_approval] || ticketing_provider.requires_approval?
        )
      else
        sync_failed!(result[:error], auth_error: result[:auth_error], rate_limited: result[:rate_limited])
      end

      result
    rescue TicketingAdapters::AuthenticationError => e
      sync_failed!(e.message, auth_error: true)
      { success: false, error: e.message, auth_error: true }
    rescue TicketingAdapters::RateLimitError => e
      ticketing_provider.record_rate_limit!(resets_at: e.resets_at)
      sync_failed!(e.message, rate_limited: true)
      { success: false, error: e.message, rate_limited: true }
    rescue StandardError => e
      sync_failed!(e.message)
      { success: false, error: e.message }
    end
  end

  # Update external provider with current inventory
  def push_inventory!
    return { success: false, error: "Not live" } unless status_live?
    return { success: false, error: "Cannot sync" } unless ticketing_provider.can_sync?

    adapter = ticketing_provider.adapter
    result = adapter.update_inventory(self)

    if result[:success]
      update!(last_synced_at: Time.current, sync_errors: [])
    else
      add_sync_error(result[:error])
    end

    result
  end

  # Pull sales from external provider
  def pull_sales!
    return { success: false, error: "Not live" } unless status_live?
    return { success: false, error: "Cannot sync" } unless ticketing_provider.can_sync?

    adapter = ticketing_provider.adapter
    result = adapter.fetch_sales(self)

    if result[:success]
      process_sales(result[:sales])
      update!(last_synced_at: Time.current, sync_errors: [])
    else
      add_sync_error(result[:error])
    end

    result
  end

  # ============================================
  # Display Helpers
  # ============================================

  def display_name
    "#{show_ticketing.show.display_name} on #{ticketing_provider.name}"
  end

  def provider_name
    ticketing_provider.name
  end

  def status_label
    case status
    when "pending_data" then "Missing Data"
    when "ready" then "Ready to Publish"
    when "pending_sync" then "Queued"
    when "syncing" then "Syncing..."
    when "pending_approval" then "Awaiting Approval"
    when "live" then "Live"
    when "sync_failed" then "Sync Failed"
    when "auth_expired" then "Auth Expired"
    when "paused" then "Paused"
    when "ended" then "Ended"
    when "manual_required" then "Action Required"
    when "manual_confirmed" then "Confirmed"
    else status.titleize
    end
  end

  def status_color
    case status
    when "live", "manual_confirmed" then "green"
    when "pending_data", "ready", "pending_sync", "syncing", "pending_approval" then "yellow"
    when "sync_failed", "auth_expired", "manual_required" then "red"
    when "paused" then "gray"
    when "ended" then "gray"
    else "gray"
    end
  end

  private

  def initialize_status
    if manual_provider?
      update!(status: data_complete? ? :manual_required : :pending_data)
    else
      update!(status: data_complete? ? :ready : :pending_data)
    end
  end

  def calculate_next_sync_time
    # Default: sync every 15 minutes for active listings
    15.minutes.from_now
  end

  def add_sync_error(error)
    errors_list = sync_errors || []
    errors_list << {
      message: error,
      at: Time.current.iso8601
    }
    # Keep only last 10 errors
    self.sync_errors = errors_list.last(10)
  end

  def process_sales(sales_data)
    return if sales_data.blank?

    sales_data.each do |sale_data|
      offer = ticket_offers.find_by(external_offer_id: sale_data[:offer_id])
      next unless offer

      # Skip if already recorded
      next if offer.ticket_sales.exists?(external_sale_id: sale_data[:sale_id])

      # Create sale record
      sale = offer.ticket_sales.create!(
        show_ticket_tier: offer.show_ticket_tier,
        external_sale_id: sale_data[:sale_id],
        quantity: sale_data[:quantity],
        total_seats: sale_data[:quantity] * offer.seats_per_offer,
        total_cents: sale_data[:total_cents],
        customer_name: sale_data[:customer_name],
        customer_email: sale_data[:customer_email],
        customer_phone: sale_data[:customer_phone],
        purchased_at: sale_data[:purchased_at],
        synced_at: Time.current
      )

      # Update tier availability
      show_ticketing.process_sale!(offer.show_ticket_tier_id, sale.total_seats)
    end
  end
end

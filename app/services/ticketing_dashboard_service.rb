# frozen_string_literal: true

# Service to calculate ticketing dashboard metrics and issues
# Implements the "opt-out" model where shows are assumed to need listings
# Updated to support new ProductionTicketingSetup architecture
class TicketingDashboardService
  attr_reader :organization

  def initialize(organization)
    @organization = organization
  end

  # ============================================
  # Main Dashboard Data
  # ============================================

  def dashboard_data
    {
      summary: summary_metrics,
      issues: all_issues,
      providers: provider_status,
      setups: production_setups_status,
      recent_activity: recent_activity
    }
  end

  def summary_metrics
    {
      total_shows_needing_tickets: shows_needing_tickets.count,
      shows_fully_listed: shows_fully_listed.count,
      shows_with_issues: shows_with_issues.count,
      active_providers: active_providers.count,
      providers_needing_attention: providers_needing_attention.count,
      active_setups: active_setups.count,
      total_remote_events: remote_events.count,
      total_sales_this_month: total_sales_this_month,
      revenue_this_month: revenue_this_month
    }
  end

  # ============================================
  # Issues (Things Needing Attention)
  # ============================================

  def all_issues
    {
      missing_listings: missing_listings_issues,
      sync_failed: sync_failed_issues,
      pending_sync: pending_sync_issues,
      auth_expired: auth_expired_issues,
      orphaned_events: orphaned_events_issues,
      setup_incomplete: setup_incomplete_issues
    }
  end

  def total_issue_count
    all_issues.values.sum(&:count)
  end

  # Shows that should have listings but don't have remote events
  def missing_listings_issues
    issues = []

    active_setups.each do |setup|
      setup.shows_to_list.each do |show|
        setup.provider_setups.enabled.each do |provider_setup|
          provider = provider_setup.ticketing_provider
          next unless setup.should_list?(show, provider)

          # Check if remote event exists
          remote_event = setup.remote_ticketing_events.find_by(
            show: show,
            ticketing_provider: provider
          )

          if remote_event.nil? || remote_event.deleted?
            issues << {
              type: :missing_listing,
              show: show,
              production: setup.production,
              provider: provider,
              setup: setup,
              message: "#{show.display_name} not listed on #{provider.name}"
            }
          end
        end
      end
    end

    issues
  end

  # Remote events that failed to sync
  def sync_failed_issues
    remote_events.sync_status_error.includes(:show, :ticketing_provider).map do |event|
      {
        type: :sync_failed,
        remote_event: event,
        show: event.show,
        provider: event.ticketing_provider,
        error_message: event.last_sync_error,
        message: "Sync failed: #{event.last_sync_error || 'Unknown error'}"
      }
    end
  end

  # Remote events pending sync
  def pending_sync_issues
    remote_events.where(sync_status: [ :pending_update, :pending_delete ]).includes(:show, :ticketing_provider).map do |event|
      {
        type: :pending_sync,
        remote_event: event,
        show: event.show,
        provider: event.ticketing_provider,
        message: "Pending #{event.sync_status.gsub('pending_', '')}"
      }
    end
  end

  # Providers with expired auth
  def auth_expired_issues
    active_providers.reject(&:credentials_healthy?).map do |provider|
      {
        type: :auth_expired,
        provider: provider,
        message: "#{provider.name} needs re-authentication"
      }
    end
  end

  # Remote events that exist on provider but show is excluded/deleted
  def orphaned_events_issues
    remote_events.sync_status_orphaned.includes(:show, :ticketing_provider).map do |event|
      {
        type: :orphaned_event,
        remote_event: event,
        show: event.show,
        provider: event.ticketing_provider,
        message: "Orphaned event on #{event.ticketing_provider.name}"
      }
    end
  end

  # Setups that aren't fully configured
  def setup_incomplete_issues
    organization.production_ticketing_setups.status_draft.map do |setup|
      {
        type: :setup_incomplete,
        setup: setup,
        production: setup.production,
        message: "Ticketing setup for #{setup.production.name} is incomplete"
      }
    end
  end

  # ============================================
  # Shows Analysis
  # ============================================

  # All upcoming shows that should have ticket listings
  def shows_needing_tickets
    @shows_needing_tickets ||= begin
      show_ids = active_setups.flat_map { |setup| setup.shows_to_list.pluck(:id) }.uniq
      Show.where(id: show_ids).order(:date_and_time)
    end
  end

  # Shows that have remote events on ALL configured providers
  def shows_fully_listed
    shows_needing_tickets.select do |show|
      active_setups.all? do |setup|
        expected_providers = setup.provider_setups.enabled.map(&:ticketing_provider)
        expected_providers.all? do |provider|
          next true unless setup.should_list?(show, provider)

          remote_event = setup.remote_ticketing_events.find_by(
            show: show,
            ticketing_provider: provider
          )
          remote_event&.sync_status_synced?
        end
      end
    end
  end

  # Shows with at least one issue
  def shows_with_issues
    shows_needing_tickets.select do |show|
      active_setups.any? do |setup|
        remote_events = setup.remote_ticketing_events.where(show: show)
        remote_events.empty? || remote_events.any? { |e| e.sync_status_error? || e.sync_status.to_s.start_with?("pending") }
      end
    end
  end

  # ============================================
  # Production Ticketing Setups
  # ============================================

  def active_setups
    # Query the model directly to avoid delegation issues on the association proxy
    @active_setups ||= ProductionTicketingSetup.where(organization_id: organization.id).active_setups.includes(:production, :provider_setups)
  end

  def production_setups_status
    organization.production_ticketing_setups.includes(:production, :provider_setups, :remote_ticketing_events).map do |setup|
      {
        setup: setup,
        production: setup.production,
        status: setup.status,
        providers_count: setup.provider_setups.enabled.count,
        shows_to_list: setup.shows_to_list.count,
        remote_events_count: setup.remote_ticketing_events.where.not(sync_status: :deleted).count,
        synced_count: setup.remote_ticketing_events.sync_status_synced.count,
        issues_count: setup.remote_ticketing_events.where(sync_status: [ :error, :orphaned ]).count
      }
    end
  end

  # ============================================
  # Remote Events
  # ============================================

  def remote_events
    @remote_events ||= RemoteTicketingEvent.joins(production_ticketing_setup: :production)
                                            .where(productions: { organization_id: organization.id })
  end

  # ============================================
  # Provider Status
  # ============================================

  def active_providers
    @active_providers ||= organization.ticketing_providers.status_active
  end

  def providers_needing_attention
    active_providers.select do |provider|
      !provider.credentials_healthy? || provider.rate_limited?
    end
  end

  def provider_status
    active_providers.map do |provider|
      remote_for_provider = remote_events.where(ticketing_provider: provider)
      {
        provider: provider,
        healthy: provider.credentials_healthy? && !provider.rate_limited?,
        credentials_valid: provider.credentials_valid?,
        rate_limited: provider.rate_limited?,
        rate_limited_until: provider.rate_limited_until,
        last_synced_at: provider.last_synced_at,
        events_count: remote_for_provider.sync_status_synced.count,
        issues_count: remote_for_provider.where(sync_status: [ :error, :orphaned ]).count
      }
    end
  end

  # ============================================
  # Activity & Sales
  # ============================================

  def recent_activity
    WebhookLog.joins(:ticketing_provider)
              .where(ticketing_providers: { organization_id: organization.id })
              .recent
              .limit(20)
  end

  def total_sales_this_month
    remote_events.where(
      "remote_ticketing_events.updated_at >= ?",
      Time.current.beginning_of_month
    ).sum(:tickets_sold)
  end

  def revenue_this_month
    remote_events.where(
      "remote_ticketing_events.updated_at >= ?",
      Time.current.beginning_of_month
    ).sum(:revenue_cents) / 100.0
  end

  # ============================================
  # Sync Operations
  # ============================================

  # Queue sync for all active setups
  def sync_all!
    active_setups.each do |setup|
      TicketingSetupSyncJob.perform_later(setup.id)
    end
  end

  # Retry failed remote events
  def retry_failed!
    remote_events.sync_status_error.find_each do |event|
      event.update!(sync_status: :pending_update)
    end

    sync_all!
  end
end

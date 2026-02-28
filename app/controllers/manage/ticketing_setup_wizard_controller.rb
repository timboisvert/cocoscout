# frozen_string_literal: true

module Manage
  # Simplified wizard for linking ticketing provider events to shows.
  # Monitor-only mode: we pull events from providers, not push to them.
  #
  # Flow:
  # 1. Select production
  # 2. Select providers to monitor
  # 3. Fetch & link events from providers to shows
  # 4. Done - creates ProductionTicketingSetup
  class TicketingSetupWizardController < ManageController
    before_action :load_wizard_state
    before_action :require_production, only: [ :providers, :save_providers, :link_events, :fetch_events, :save_links, :create_setup ]

    # ============================================
    # Step 1: Start / Select Production
    # ============================================

    def start
      # Clear any existing wizard state
      session.delete(:ticketing_setup_wizard)
      @wizard_state = { step: "production", started_at: Time.current.iso8601 }

      # If editing an existing setup, load its data
      if params[:edit].present?
        setup = ProductionTicketingSetup.find_by(id: params[:edit])
        if setup && setup.organization_id == Current.organization.id
          initialize_wizard_from_setup(setup)
          save_wizard_state
          redirect_to manage_ticketing_setup_wizard_production_path and return
        end
      end

      # If production_id is passed, pre-select it and skip to providers
      if params[:production_id].present?
        production = Current.organization.productions.find_by(id: params[:production_id])
        if production
          @wizard_state[:production_id] = production.id
          @wizard_state[:step] = "providers"
          save_wizard_state
          redirect_to manage_ticketing_setup_wizard_providers_path and return
        end
      end

      save_wizard_state
      redirect_to manage_ticketing_setup_wizard_production_path
    end

    def production
      @available_productions = Current.organization.productions
        .includes(:shows)
        .order(:name)
        .select { |p| p.shows.any? }
    end

    def save_production
      production_id = params[:production_id]

      unless production_id.present?
        flash[:alert] = "Please select a production"
        redirect_to manage_ticketing_setup_wizard_production_path and return
      end

      production = Current.organization.productions.find_by(id: production_id)
      unless production
        flash[:alert] = "Production not found"
        redirect_to manage_ticketing_setup_wizard_production_path and return
      end

      @wizard_state[:production_id] = production.id
      @wizard_state[:step] = "providers"
      save_wizard_state

      redirect_to manage_ticketing_setup_wizard_providers_path
    end

    # ============================================
    # Step 2: Select Providers
    # ============================================

    def providers
      @production = load_selected_production
      @available_providers = Current.organization.ticketing_providers.active
      @selected_ids = @wizard_state[:provider_ids] || []
    end

    def save_providers
      provider_ids = Array(params[:provider_ids]).map(&:to_i).reject(&:zero?)

      if provider_ids.empty?
        flash[:alert] = "Please select at least one provider"
        redirect_to manage_ticketing_setup_wizard_providers_path and return
      end

      # Verify all selected providers belong to org
      valid_ids = Current.organization.ticketing_providers.active.where(id: provider_ids).pluck(:id)
      if valid_ids.empty?
        flash[:alert] = "Invalid provider selection"
        redirect_to manage_ticketing_setup_wizard_providers_path and return
      end

      @wizard_state[:provider_ids] = valid_ids
      @wizard_state[:step] = "link"
      save_wizard_state

      redirect_to manage_ticketing_setup_wizard_link_events_path
    end

    # ============================================
    # Step 3: Link Events
    # ============================================

    def link_events
      @production = load_selected_production
      @providers = selected_providers

      # Check if providers have been synced (have ProviderEvents)
      @provider_events_exist = ProviderEvent.where(ticketing_provider_id: @providers.pluck(:id)).exists?
      @providers_needing_sync = @providers.select { |p| p.provider_events.empty? }

      unless @provider_events_exist
        # No provider events synced - show "needs sync" state
        render :link_events_needs_sync
        return
      end

      # Get shows for this production
      @shows = @production.shows.upcoming.order(:date_and_time)

      # Calculate the date range of shows in this production (with buffer)
      show_dates = @shows.pluck(:date_and_time).compact
      if show_dates.any?
        earliest_show = show_dates.min - 7.days
        latest_show = show_dates.max + 7.days
        date_range = earliest_show..latest_show
      else
        date_range = nil
      end

      # Get remote events for these providers, filtered to relevant date range
      remote_events = RemoteTicketingEvent
        .where(ticketing_provider_id: @wizard_state[:provider_ids])
        .where(organization_id: Current.organization.id)

      # Only include events with dates near our shows
      if date_range
        remote_events = remote_events.where(event_date: date_range)
      end

      # Run smart matching with production scope
      matcher = TicketingEventMatcherService.new(Current.organization, production: @production)

      # Run matching on each unlinked event
      @auto_linked = []
      @needs_review = []
      @no_match = []

      remote_events.where(show_id: nil).find_each do |event|
        match = matcher.find_best_match(event)

        if match[:confidence] >= TicketingEventMatcherService::HIGH_CONFIDENCE
          # Auto-link
          matcher.link_event_to_show(event, match[:show], match[:confidence])
          @auto_linked << { event: event, show: match[:show], confidence: match[:confidence] }
        elsif match[:confidence] >= TicketingEventMatcherService::LOW_CONFIDENCE
          # Needs review - store suggestion
          event.update!(
            suggested_show_id: match[:show].id,
            match_confidence: match[:confidence],
            match_reasons: match[:reasons]
          )
          @needs_review << { event: event, suggested_show: match[:show], confidence: match[:confidence] }
        else
          @no_match << event
        end
      end

      # Also include already-linked events for this production
      @already_linked = remote_events
        .joins(:show)
        .where(shows: { production_id: @production.id })
        .includes(:show)

      # If everything is matched and nothing needs review, go straight to done
      if @needs_review.empty? && @no_match.empty? && @auto_linked.any?
        flash[:notice] = "#{@auto_linked.count} events automatically linked based on matching dates and names!"
        create_setup
        nil
      end
    end

    def fetch_events
      fetch_events_and_return
    end

    # Fetches events from providers and redirects back to link_events
    def fetch_events_and_return
      @production = load_selected_production
      providers = selected_providers

      total_events = 0
      total_occurrences = 0
      errors = []

      providers.each do |provider|
        begin
          service = ProviderSyncService.new(provider)
          stats = service.sync!
          total_events += stats[:events_created] + stats[:events_updated]
          total_occurrences += stats[:occurrences_created] + stats[:occurrences_updated]
          errors.concat(stats[:errors]) if stats[:errors].any?
        rescue => e
          errors << "#{provider.name}: #{e.message}"
          Rails.logger.error "[TicketingWizard] Failed to sync #{provider.name}: #{e.message}"
        end
      end

      if errors.any?
        flash[:alert] = "Some providers failed: #{errors.first(3).join(', ')}"
      elsif total_occurrences > 0
        flash[:notice] = "Synced #{total_events} events with #{total_occurrences} occurrences from #{providers.count} provider(s)"
      end

      redirect_to manage_ticketing_setup_wizard_link_events_path
    end

    def save_links
      @production = load_selected_production
      matcher = TicketingEventMatcherService.new(Current.organization)

      # Process confirmed links from the form
      # links come as { remote_event_id => show_id } pairs
      links = params[:links] || {}

      links.each do |remote_event_id, show_id|
        next unless show_id.present?

        event = RemoteTicketingEvent.find_by(id: remote_event_id)
        show = Show.find_by(id: show_id)
        next unless event && show

        matcher.link_event_to_show(event, show, 1.0) # User-confirmed = 100% confidence
      end

      # Now create the setup
      create_setup
    end

    # ============================================
    # Step 4: Create Setup
    # ============================================

    def create_setup
      @production = load_selected_production

      ActiveRecord::Base.transaction do
        # Create or update the setup
        @setup = if @wizard_state[:editing_setup_id]
          ProductionTicketingSetup.find(@wizard_state[:editing_setup_id])
        else
          ProductionTicketingSetup.new
        end

        @setup.assign_attributes(
          production: @production,
          organization: Current.organization,
          status: "active",
          created_by: current_user.person,
          wizard_completed_at: Time.current,
          activated_at: Time.current
        )

        @setup.save!

        # Create provider setups
        @wizard_state[:provider_ids].each do |provider_id|
          provider = TicketingProvider.find(provider_id)
          @setup.provider_setups.find_or_create_by!(ticketing_provider: provider) do |ps|
            ps.enabled = true
          end
        end

        # Associate all linked remote events for this production with the setup
        linked_events = RemoteTicketingEvent
          .where(ticketing_provider_id: @wizard_state[:provider_ids])
          .where(organization_id: Current.organization.id)
          .joins(:show)
          .where(shows: { production_id: @production.id })

        linked_events.update_all(production_ticketing_setup_id: @setup.id)
      end

      # Clear wizard state
      session.delete(:ticketing_setup_wizard)

      flash[:notice] = "Ticketing setup complete! Sales will be synced automatically."
      redirect_to manage_show_ticketing_production_path(@production)

    rescue => e
      Rails.logger.error "[TicketingWizard] Setup failed: #{e.message}"
      flash[:alert] = "Failed to create setup: #{e.message}"
      redirect_to manage_ticketing_setup_wizard_link_events_path
    end

    def cancel
      session.delete(:ticketing_setup_wizard)
      flash[:notice] = "Wizard cancelled"
      redirect_to manage_show_ticketings_path
    end

    private

    def load_wizard_state
      @wizard_state = session[:ticketing_setup_wizard]&.deep_symbolize_keys || {}
    end

    def save_wizard_state
      session[:ticketing_setup_wizard] = @wizard_state
    end

    def require_production
      unless @wizard_state[:production_id].present?
        redirect_to manage_ticketing_setup_wizard_production_path
      end
    end

    def load_selected_production
      return nil unless @wizard_state[:production_id]
      Current.organization.productions.find_by(id: @wizard_state[:production_id])
    end

    def selected_providers
      return [] unless @wizard_state[:provider_ids].present?
      Current.organization.ticketing_providers.where(id: @wizard_state[:provider_ids])
    end

    def initialize_wizard_from_setup(setup)
      @wizard_state = {
        editing_setup_id: setup.id,
        production_id: setup.production_id,
        provider_ids: setup.provider_setups.pluck(:ticketing_provider_id),
        event_links: setup.remote_ticketing_events.where.not(show_id: nil).pluck(:id, :show_id).to_h,
        step: "production",
        started_at: Time.current.iso8601
      }
      save_wizard_state
    end

    def fetch_events_from_provider(provider)
      adapter = provider.adapter
      result = adapter.list_events

      unless result[:success]
        Rails.logger.error "[TicketingWizard] Failed to fetch events: #{result[:error]}"
        return []
      end

      raw_events = result[:events] || []
      events = []
      raw_events.each do |raw|
        event = RemoteTicketingEvent.find_or_initialize_by(
          ticketing_provider: provider,
          external_event_id: raw[:id]
        )

        event.assign_attributes(
          organization: Current.organization,
          event_name: raw[:name] || raw[:title],
          event_date: raw[:start_date] || raw[:start],
          venue_name: raw[:venue]&.dig(:name) || raw[:venue_name],
          tickets_sold: raw[:tickets_sold] || 0,
          tickets_available: raw[:tickets_available] || raw[:capacity] || 0,
          revenue_cents: raw[:revenue_cents] || 0,
          external_url: raw[:url] || raw[:external_url],
          remote_status: map_provider_status(raw[:status]),
          raw_data: raw,
          last_synced_at: Time.current
        )

        event.save!
        events << event
      end

      events
    end

    def map_provider_status(status)
      case status.to_s.downcase
      when "live", "published", "on_sale" then "live"
      when "draft", "unpublished" then "draft"
      when "ended", "completed", "closed" then "sales_closed"
      when "canceled", "cancelled" then "canceled"
      else "live"
      end
    end
  end
end

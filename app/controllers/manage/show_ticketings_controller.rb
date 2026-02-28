# frozen_string_literal: true

module Manage
  class ShowTicketingsController < Manage::ManageController
    before_action :set_production_for_toggle, only: %i[enable_production disable_production]
    before_action :set_production_for_engine, only: %i[sync_production activate_engine pause_engine]
    before_action :set_production, except: %i[index enable_production disable_production sync_production activate_engine pause_engine]
    before_action :set_show, only: %i[show setup create_setup edit update sync toggle_exclude sync_show edit_override update_override]
    before_action :set_show_ticketing, only: %i[show edit update sync]
    before_action :set_setup_and_rule, only: %i[toggle_exclude sync_show edit_override update_override]

    def index
      all_productions = Current.user.accessible_productions
        .includes(:shows, :contract, :production_ticketing_setups)
        .order(:name)

      # Productions with ticketing enabled (already opted in)
      @enabled_productions = all_productions.select { |p| p.ticketing_enabled? && p.shows.upcoming.any? }

      # Productions available to enable (not opted in, but have upcoming shows)
      @available_productions = all_productions.select { |p| !p.ticketing_enabled? && p.shows.upcoming.any? }
    end

    def enable_production
      @production.update!(ticketing_enabled: true)

      # Check if setup exists, redirect to wizard if not
      if @production.ticketing_setup.present?
        redirect_to manage_production_show_ticketings_path(@production), notice: "Ticketing enabled for #{@production.name}."
      else
        # Redirect to wizard to set up the engine
        redirect_to manage_ticketing_setup_wizard_start_path(production_id: @production.id), notice: "Let's set up ticketing for #{@production.name}."
      end
    end

    def disable_production
      @production.update!(ticketing_enabled: false)
      redirect_to manage_show_ticketings_path, notice: "Ticketing disabled for #{@production.name}."
    end

    # ============================================
    # Engine actions
    # ============================================

    def sync_production
      setup = @production.ticketing_setup
      if setup&.status_active?
        TicketingSetupSyncJob.perform_later(setup.id)
        redirect_to manage_production_show_ticketings_path(@production), notice: "Sync started..."
      else
        redirect_to manage_production_show_ticketings_path(@production), alert: "Cannot sync - engine is not active."
      end
    end

    def activate_engine
      setup = @production.ticketing_setup
      if setup&.activate!
        TicketingSetupSyncJob.perform_later(setup.id)
        redirect_to manage_production_show_ticketings_path(@production), notice: "Engine activated! Syncing..."
      else
        redirect_to manage_production_show_ticketings_path(@production), alert: "Cannot activate engine."
      end
    end

    def pause_engine
      setup = @production.ticketing_setup
      if setup&.pause!
        redirect_to manage_production_show_ticketings_path(@production), notice: "Engine paused."
      else
        redirect_to manage_production_show_ticketings_path(@production), alert: "Cannot pause engine."
      end
    end

    # ============================================
    # Production dashboard
    # ============================================

    def production
      @setup = @production.ticketing_setup
      @shows = @production.shows.upcoming.includes(:location, :production).order(:date_and_time)
      @show_ticketings = ShowTicketing.where(show_id: @shows.pluck(:id)).index_by(&:show_id)

      # Load remote events to show sync status per provider
      if @setup
        @remote_events = @setup.remote_ticketing_events
          .includes(:ticketing_provider, :show)
          .where(show_id: @shows.pluck(:id))
          .group_by(&:show_id)

        # Load per-show rules (exclusions, overrides)
        @ticketing_rules = @setup.show_ticketing_rules
          .where(show_id: @shows.pluck(:id))
          .index_by(&:show_id)
      else
        @remote_events = {}
        @ticketing_rules = {}
      end

      # Load recent activities
      @recent_activities = TicketingActivity.for_production(@production.id)
    end

    def show
      @ticket_tiers = @show_ticketing.show_ticket_tiers.ordered
      @listings = @show_ticketing.ticket_listings.includes(:ticketing_provider)
      @recent_sales = TicketSale.joins(ticket_offer: :ticket_listing)
        .where(ticket_listings: { show_ticketing_id: @show_ticketing.id })
        .order(purchased_at: :desc)
        .limit(10)
    end

    def setup
      # Set up ticketing for a show
      @seating_configurations = Current.organization.seating_configurations.order(:name)
      @show_ticketing = ShowTicketing.new(show: @show)

      # Pre-select configuration if location matches
      if @show.location_id.present?
        matching_config = @seating_configurations.find_by(location_id: @show.location_id)
        @show_ticketing.seating_configuration = matching_config if matching_config
      end
    end

    def create_setup
      @show_ticketing = ShowTicketing.new(setup_params.merge(show: @show))

      if @show_ticketing.save
        # Copy tiers from seating configuration
        @show_ticketing.copy_tiers_from_configuration!

        redirect_to manage_show_ticketing_path(@production, @show), notice: "Ticketing set up successfully."
      else
        @seating_configurations = Current.organization.seating_configurations.order(:name)
        render :setup, status: :unprocessable_entity
      end
    end

    def edit
      @seating_configurations = Current.organization.seating_configurations.order(:name)
    end

    def update
      if @show_ticketing.update(update_params)
        redirect_to manage_show_ticketing_path(@production, @show), notice: "Ticketing updated."
      else
        @seating_configurations = Current.organization.seating_configurations.order(:name)
        render :edit, status: :unprocessable_entity
      end
    end

    def sync
      # Sync all listings for this show
      @show_ticketing.ticket_listings.active.find_each(&:sync!)

      redirect_to manage_show_ticketing_path(@production, @show), notice: "Sync initiated."
    end

    # ============================================
    # Show-level override actions (engine-based)
    # ============================================

    def toggle_exclude
      if @rule&.rule_type_exclude?
        # Remove exclusion
        @rule.destroy
        TicketingActivity.log!(@production, "show_included", "Re-included show: #{@show.display_name}", show: @show)
        redirect_to manage_production_show_ticketings_path(@production), notice: "Show will be included in ticketing."
      else
        # Create exclusion
        @rule&.destroy # Remove any existing rule
        @setup.show_ticketing_rules.create!(show: @show, rule_type: :exclude)
        TicketingActivity.log!(@production, "show_excluded", "Excluded show: #{@show.display_name}", show: @show)
        redirect_to manage_production_show_ticketings_path(@production), notice: "Show excluded from ticketing."
      end

      # Queue sync to update provider
      TicketingSetupSyncJob.perform_later(@setup.id) if @setup.status_active?
    end

    def sync_show
      if @setup&.status_active?
        # Queue sync that will handle this show
        TicketingSetupSyncJob.perform_later(@setup.id, show_ids: [ @show.id ])
        redirect_to manage_production_show_ticketings_path(@production), notice: "Syncing show..."
      else
        redirect_to manage_production_show_ticketings_path(@production), alert: "Engine is not active."
      end
    end

    def edit_override
      # Load existing override or build a new one
      @rule ||= @setup.show_ticketing_rules.build(show: @show, rule_type: :override)
      @override_data = @rule.override_data || {}
      @default_tiers = @setup.default_pricing_tiers || []
    end

    def update_override
      override_data = build_override_data_from_params

      if override_data.values.all?(&:blank?)
        # No overrides, remove the rule if it exists
        @rule&.destroy
        redirect_to manage_production_show_ticketings_path(@production), notice: "Overrides cleared."
      else
        if @rule.nil? || @rule.new_record?
          @rule = @setup.show_ticketing_rules.build(show: @show, rule_type: :override)
        elsif !@rule.rule_type_override?
          @rule.rule_type = :override
        end

        @rule.override_data = override_data

        if @rule.save
          TicketingActivity.log!(@production, "show_override", "Updated override for: #{@show.display_name}", show: @show)
          TicketingSetupSyncJob.perform_later(@setup.id, show_ids: [ @show.id ]) if @setup.status_active?
          redirect_to manage_production_show_ticketings_path(@production), notice: "Override saved."
        else
          @override_data = override_data
          @default_tiers = @setup.default_pricing_tiers || []
          render :edit_override, status: :unprocessable_entity
        end
      end
    end

    private

    def set_production
      @production = Current.user.accessible_productions.find(params[:production_id])
      # Ensure production has ticketing enabled
      unless @production.ticketing_enabled?
        redirect_to manage_ticketing_index_path, alert: "Ticketing is not enabled for this production."
      end
    end

    def set_production_for_toggle
      @production = Current.user.accessible_productions.find(params[:production_id])
    end

    def set_production_for_engine
      @production = Current.user.accessible_productions.find(params[:production_id])
      unless @production.ticketing_enabled?
        redirect_to manage_show_ticketings_path, alert: "Ticketing is not enabled for this production."
      end
    end

    def set_show
      @show = @production.shows.find(params[:show_id])
    end

    def set_show_ticketing
      @show_ticketing = ShowTicketing.find_by!(show: @show)
    end

    def setup_params
      params.require(:show_ticketing).permit(
        :seating_configuration_id,
        :total_capacity,
        :total_available
      )
    end

    def update_params
      params.require(:show_ticketing).permit(
        :total_capacity,
        :total_available,
        :total_held
      )
    end

    def set_setup_and_rule
      @setup = @production.ticketing_setup
      unless @setup
        redirect_to manage_production_show_ticketings_path(@production), alert: "No ticketing setup found."
        return
      end
      @rule = @setup.show_ticketing_rules.find_by(show: @show)
    end

    def build_override_data_from_params
      data = {}

      # Title override
      data["title"] = params[:override_title] if params[:override_title].present?

      # Description override
      data["description"] = params[:override_description] if params[:override_description].present?

      # Pricing tiers override
      if params[:pricing_tiers].present?
        tiers = []
        params[:pricing_tiers].each do |_index, tier_params|
          next if tier_params[:name].blank?
          tiers << {
            "name" => tier_params[:name],
            "price_cents" => (tier_params[:price].to_f * 100).to_i,
            "quantity" => tier_params[:quantity].to_i
          }
        end
        data["pricing_tiers"] = tiers if tiers.any?
      end

      data
    end
  end
end

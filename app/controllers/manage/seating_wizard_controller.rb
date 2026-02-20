# frozen_string_literal: true

module Manage
  class SeatingWizardController < Manage::ManageController
    before_action :ensure_user_is_global_manager
    before_action :load_wizard_state, except: [ :basics, :save_basics ]
    before_action :load_wizard_state_or_initialize, only: [ :basics, :save_basics ]

    # Step 1: Basics - Name and location
    def basics
      @wizard_state[:name] ||= ""
      @wizard_state[:location_id] ||= nil
      @wizard_state[:location_space_id] ||= nil
      @locations = Current.organization.locations.order(:name)
    end

    def save_basics
      @wizard_state[:name] = params[:name]&.strip
      @wizard_state[:location_id] = params[:location_id].presence
      @wizard_state[:location_space_id] = params[:location_space_id].presence

      errors = []
      errors << "Please enter a configuration name" if @wizard_state[:name].blank?
      errors << "Please select a location" if @wizard_state[:location_id].blank?

      if errors.any?
        @locations = Current.organization.locations.order(:name)
        flash.now[:alert] = errors.join(". ")
        render :basics, status: :unprocessable_entity and return
      end

      save_wizard_state
      redirect_to manage_seating_wizard_zones_path
    end

    # Step 2: Zones - Define seating areas
    def zones
      redirect_to manage_seating_wizard_basics_path and return if @wizard_state[:name].blank? || @wizard_state[:location_id].blank?

      @wizard_state[:zones] ||= []
    end

    def save_zones
      @wizard_state[:zones] = parse_zones(params[:zones])

      if @wizard_state[:zones].blank?
        flash.now[:alert] = "Please add at least one zone"
        render :zones, status: :unprocessable_entity and return
      end

      save_wizard_state
      redirect_to manage_seating_wizard_review_path
    end

    # Step 3: Review
    def review
      redirect_to manage_seating_wizard_basics_path and return if @wizard_state[:name].blank?
      redirect_to manage_seating_wizard_zones_path and return if @wizard_state[:zones].blank?

      @location = Location.find(@wizard_state[:location_id]) if @wizard_state[:location_id].present?
      @location_space = LocationSpace.find(@wizard_state[:location_space_id]) if @wizard_state[:location_space_id].present?
      @total_capacity = calculate_total_capacity(@wizard_state[:zones])
    end

    # Final: Create the configuration
    def create
      if @wizard_state[:name].blank?
        flash[:alert] = "Your wizard session has expired. Please start again."
        redirect_to manage_seating_configurations_path and return
      end

      ActiveRecord::Base.transaction do
        @seating_configuration = Current.organization.seating_configurations.create!(
          name: @wizard_state[:name],
          location_id: @wizard_state[:location_id],
          location_space_id: @wizard_state[:location_space_id],
          status: :active
        )

        @wizard_state[:zones].each_with_index do |zone_data, index|
          @seating_configuration.seating_zones.create!(
            name: zone_data[:name] || zone_data["name"],
            zone_type: zone_data[:zone_type] || zone_data["zone_type"],
            unit_count: (zone_data[:unit_count] || zone_data["unit_count"]).to_i,
            capacity_per_unit: (zone_data[:capacity_per_unit] || zone_data["capacity_per_unit"]).to_i,
            position: index
          )
        end
      end

      clear_wizard_state
      redirect_to manage_seating_configuration_path(@seating_configuration),
                  notice: "Seating configuration created successfully"
    end

    # Cancel the wizard
    def cancel
      clear_wizard_state
      redirect_to manage_seating_configurations_path, notice: "Configuration creation cancelled"
    end

    private

    def load_wizard_state_or_initialize
      @wizard_state = session[:seating_wizard] || {}
      @wizard_state = @wizard_state.with_indifferent_access
    end

    def load_wizard_state
      @wizard_state = (session[:seating_wizard] || {}).with_indifferent_access
      redirect_to manage_seating_wizard_basics_path and return if @wizard_state.blank?
    end

    def save_wizard_state
      session[:seating_wizard] = @wizard_state.to_h
    end

    def clear_wizard_state
      session.delete(:seating_wizard)
    end

    def parse_zones(zones_params)
      return [] if zones_params.blank?

      zones_params.values.map do |zone|
        next if zone[:_destroy] == "1" || zone["_destroy"] == "1"
        next if zone[:name].blank? && zone["name"].blank?

        zone_type = zone[:zone_type] || zone["zone_type"] || "individual_seats"

        # Get unit_count and capacity_per_unit based on zone type
        # Each zone type has its own input fields (e.g., unit_count_tables, capacity_per_unit_rows)
        # Also check for the generic hidden fields set by JavaScript
        unit_count, capacity_per_unit = extract_zone_values(zone, zone_type)

        {
          name: zone[:name] || zone["name"],
          zone_type: zone_type,
          unit_count: unit_count,
          capacity_per_unit: capacity_per_unit
        }
      end.compact
    end

    def extract_zone_values(zone, zone_type)
      # First check for generic fields (set by JavaScript hidden fields)
      if zone[:unit_count].present? || zone["unit_count"].present?
        unit_count = (zone[:unit_count] || zone["unit_count"]).to_i
        capacity_per_unit = (zone[:capacity_per_unit] || zone["capacity_per_unit"]).to_i
        return [ unit_count, capacity_per_unit ] if unit_count.positive?
      end

      # Fall back to type-specific fields
      case zone_type
      when "individual_seats"
        unit_count = (zone[:unit_count] || zone["unit_count"] || 1).to_i
        capacity_per_unit = 1
      when "tables"
        unit_count = (zone[:unit_count_tables] || zone["unit_count_tables"] || 1).to_i
        capacity_per_unit = (zone[:capacity_per_unit_tables] || zone["capacity_per_unit_tables"] || 2).to_i
      when "rows"
        unit_count = (zone[:unit_count_rows] || zone["unit_count_rows"] || 1).to_i
        capacity_per_unit = (zone[:capacity_per_unit_rows] || zone["capacity_per_unit_rows"] || 10).to_i
      when "booths"
        unit_count = (zone[:unit_count_booths] || zone["unit_count_booths"] || 1).to_i
        capacity_per_unit = (zone[:capacity_per_unit_booths] || zone["capacity_per_unit_booths"] || 4).to_i
      when "standing"
        unit_count = (zone[:unit_count_standing] || zone["unit_count_standing"] || 50).to_i
        capacity_per_unit = 1
      else
        unit_count = 1
        capacity_per_unit = 1
      end

      [ unit_count, capacity_per_unit ]
    end

    def calculate_total_capacity(zones)
      zones.sum { |z| (z[:unit_count] || z["unit_count"]).to_i * (z[:capacity_per_unit] || z["capacity_per_unit"]).to_i }
    end
  end
end

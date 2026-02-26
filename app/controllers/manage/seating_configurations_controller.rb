# frozen_string_literal: true

module Manage
  class SeatingConfigurationsController < Manage::ManageController
    before_action :set_configuration, only: %i[show edit update destroy]
    before_action :set_locations, only: %i[new create edit update]

    def index
      configurations = Current.organization.seating_configurations
        .includes(:location, :location_space, :ticket_tiers)
        .order(:name)

      # Group by location_space, with nil spaces grouped under "Other"
      @configurations_by_space = configurations.group_by(&:location_space)
      @configurations = configurations
    end

    def show
      @ticket_tiers = @configuration.ticket_tiers.ordered
      @seating_zones = @configuration.seating_zones.ordered
      @usage_count = ShowTicketing.where(seating_configuration_id: @configuration.id).count
    end

    def new
      # Redirect to the wizard for creating new configurations
      redirect_to manage_seating_wizard_basics_path
    end

    def create
      @configuration = Current.organization.seating_configurations.build(configuration_params)

      if @configuration.save
        redirect_to manage_seating_configuration_path(@configuration), notice: "Seating configuration created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @configuration.update(configuration_params)
        redirect_to manage_seating_configuration_path(@configuration), notice: "Seating configuration updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      usage_count = ShowTicketing.where(seating_configuration_id: @configuration.id).count

      if usage_count.positive?
        redirect_to manage_seating_configurations_path, alert: "Cannot delete configuration in use by #{usage_count} shows."
      else
        @configuration.destroy
        redirect_to manage_seating_configurations_path, notice: "Seating configuration deleted."
      end
    end

    private

    def set_configuration
      @configuration = Current.organization.seating_configurations.find(params[:id])
    end

    def set_locations
      @locations = Current.organization.locations.order(:name)
      @location_spaces_by_location = LocationSpace.where(location_id: @locations.pluck(:id))
        .group_by(&:location_id)
    end

    def configuration_params
      params.require(:seating_configuration).permit(
        :name,
        :description,
        :location_id,
        :location_space_id,
        seating_zones_attributes: %i[id name zone_type unit_count capacity_per_unit position _destroy]
      )
    end
  end
end

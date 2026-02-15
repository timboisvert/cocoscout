# frozen_string_literal: true

module Manage
  class SeatingConfigurationsController < Manage::ManageController
    before_action :set_configuration, only: %i[show edit update destroy]
    before_action :set_locations, only: %i[new create edit update]

    def index
      @configurations = Current.organization.seating_configurations
        .includes(:location, :location_space, :ticket_tiers)
        .order(:name)
    end

    def show
      @ticket_tiers = @configuration.ticket_tiers.ordered
      @usage_count = ShowTicketing.where(seating_configuration_id: @configuration.id).count
    end

    def new
      @configuration = Current.organization.seating_configurations.build
      @configuration.ticket_tiers.build(position: 0) # Start with one tier
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
        ticket_tiers_attributes: %i[id name description capacity default_price_cents position _destroy]
      )
    end
  end
end

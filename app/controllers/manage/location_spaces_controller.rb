# frozen_string_literal: true

module Manage
  class LocationSpacesController < ManageController
    before_action :set_location
    before_action :set_space, only: %i[update destroy set_default]

    def index
      @spaces = @location.location_spaces.by_name
    end

    def create
      @space = @location.location_spaces.build(space_params)

      if @space.save
        respond_to do |format|
          format.html { redirect_to manage_location_path(@location), notice: "Space created." }
          format.turbo_stream
        end
      else
        respond_to do |format|
          format.html { redirect_to manage_location_path(@location), alert: @space.errors.full_messages.join(", ") }
          format.turbo_stream { render turbo_stream: turbo_stream.replace("new_space_form", partial: "manage/location_spaces/form", locals: { space: @space, location: @location }) }
        end
      end
    end

    def update
      if @space.update(space_params)
        respond_to do |format|
          format.html { redirect_to manage_location_path(@location), notice: "Space updated." }
          format.turbo_stream
        end
      else
        respond_to do |format|
          format.html { redirect_to manage_location_path(@location), alert: @space.errors.full_messages.join(", ") }
          format.turbo_stream { render turbo_stream: turbo_stream.replace("space_#{@space.id}", partial: "manage/location_spaces/space", locals: { space: @space }) }
        end
      end
    end

    def destroy
      if @space.space_rentals.any? || @space.shows.any?
        redirect_to manage_location_path(@location), alert: "Cannot delete space with existing bookings or shows."
      else
        @space.destroy
        respond_to do |format|
          format.html { redirect_to manage_location_path(@location), notice: "Space deleted." }
          format.turbo_stream { render turbo_stream: turbo_stream.remove("space_#{@space.id}") }
        end
      end
    end

    def set_default
      @space.update!(default: true)
      redirect_to manage_location_path(@location), notice: "#{@space.name} set as default space."
    end

    private

    def set_location
      @location = Current.organization.locations.find(params[:location_id])
    end

    def set_space
      @space = @location.location_spaces.find(params[:id])
    end

    def space_params
      params.require(:location_space).permit(:name, :description, :capacity)
    end
  end
end

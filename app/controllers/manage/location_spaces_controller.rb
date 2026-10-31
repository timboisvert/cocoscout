# frozen_string_literal: true

module Manage
  # A location's rooms (LocationSpace; the interface says "rooms"). Each room
  # has a page of its own: its facts, what's coming up in it, and a slot where
  # a Pro module the organization has (Ticketing) renders its own card. The
  # room page itself never reads a Pro module's data (advanced ticketing plan
  # §0, Tim 2026-10-29).
  class LocationSpacesController < ManageController
    before_action :ensure_user_is_global_manager, except: %i[index show]
    before_action :set_location
    before_action :set_space, only: %i[show update destroy set_default]

    def index
      @spaces = @location.location_spaces.by_name

      respond_to do |format|
        format.html { redirect_to manage_location_path(@location) }
        format.json { render json: @spaces.map { |s| { id: s.id, name: s.display_name } } }
      end
    end

    def show
      @can_edit = Current.organization.manageable_by?(Current.user) || Current.user.superadmin?
      @coming_up = @space.upcoming_shows(limit: 12).to_a
    end

    def create
      @space = @location.location_spaces.build(space_params)

      if @space.save
        redirect_to manage_location_space_path(@location, @space), notice: "Room added."
      else
        redirect_to manage_location_path(@location), alert: @space.errors.full_messages.to_sentence
      end
    end

    def update
      if @space.update(space_params)
        redirect_to manage_location_space_path(@location, @space), notice: "Room saved.", status: :see_other
      else
        redirect_to manage_location_space_path(@location, @space), alert: @space.errors.full_messages.to_sentence
      end
    end

    def destroy
      if @space.deletable?
        @space.destroy!
        redirect_to manage_location_path(@location), notice: "Room deleted.", status: :see_other
      elsif @location.location_spaces.where.not(id: @space.id).none?
        redirect_to manage_location_space_path(@location, @space), alert: "Every location keeps at least one room."
      else
        redirect_to manage_location_space_path(@location, @space), alert: "This room has shows or bookings in it, so it stays."
      end
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey
      redirect_to manage_location_space_path(@location, @space), alert: "This room is in use (a seat chart or ticket sales point at it), so it stays."
    end

    def set_default
      @space.update!(default: true)
      redirect_to manage_location_path(@location), notice: "#{@space.name} is now the default room."
    end

    private

    def set_location
      @location = Current.organization.locations.find(params[:location_id])
    end

    def set_space
      @space = @location.location_spaces.find(params[:id])
    end

    def space_params
      params.require(:location_space).permit(:name, :description, :capacity, :default)
    end
  end
end

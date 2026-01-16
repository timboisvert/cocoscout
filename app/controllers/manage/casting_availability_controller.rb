# frozen_string_literal: true

module Manage
  class CastingAvailabilityController < Manage::ManageController
    before_action :set_production

    def index
      # Get all future shows for this production, ordered by date
      # Load them into memory once to avoid multiple queries
      @shows = @production.shows
                          .where(canceled: false)
                          .where("date_and_time >= ?", Time.current)
                          .order(:date_and_time)
                          .to_a

      # Get effective talent pool ID (shared or own)
      effective_pool = @production.effective_talent_pool
      talent_pool_id = effective_pool&.id

      # Get all cast members with headshots eager loaded in a single query
      @people = Person
                .joins(:talent_pool_memberships)
                .where(talent_pool_memberships: { talent_pool_id: talent_pool_id })
                .includes(profile_headshots: { image_attachment: :blob })
                .distinct
                .order(:name)
                .to_a

      @groups = Group
                .joins(:talent_pool_memberships)
                .where(talent_pool_memberships: { talent_pool_id: talent_pool_id })
                .includes(profile_headshots: { image_attachment: :blob })
                .distinct
                .order(:name)
                .to_a

      @cast_members = (@people + @groups).sort_by(&:name)

      # Fetch all availabilities for these shows in one query
      # Use .map(&:id) on already-loaded array instead of .pluck which triggers another query
      show_ids = @shows.map(&:id)
      all_availabilities = ShowAvailability.where(show_id: show_ids).to_a

      # Build a hash of availabilities: { "Person_1" => { show_id => show_availability }, "Group_2" => ... }
      @availabilities = {}
      @cast_members.each do |member|
        key = "#{member.class.name}_#{member.id}"
        @availabilities[key] = {}
      end

      all_availabilities.each do |availability|
        key = "#{availability.available_entity_type}_#{availability.available_entity_id}"
        @availabilities[key] ||= {}
        @availabilities[key][availability.show_id] = availability
      end
    end

    # Returns HTML for the show availability modal
    def show_modal
      @show = @production.shows
                         .includes(
                           :location,
                           poster_attachment: :blob,
                           production: { posters: { image_attachment: :blob } }
                         )
                         .find(params[:id])

      # Get effective talent pool ID (shared or own)
      effective_pool = @production.effective_talent_pool
      talent_pool_id = effective_pool&.id

      # Get all cast members with headshots eager loaded in a single query
      @people = Person
                .joins(:talent_pool_memberships)
                .where(talent_pool_memberships: { talent_pool_id: talent_pool_id })
                .includes(profile_headshots: { image_attachment: :blob })
                .distinct
                .order(:name)
                .to_a

      @groups = Group
                .joins(:talent_pool_memberships)
                .where(talent_pool_memberships: { talent_pool_id: talent_pool_id })
                .includes(profile_headshots: { image_attachment: :blob })
                .distinct
                .order(:name)
                .to_a

      @cast_members = (@people + @groups).sort_by(&:name)

      # Fetch all availabilities for this show in one query
      show_availabilities = ShowAvailability.where(show: @show).to_a

      @availabilities = {}
      show_availabilities.each do |availability|
        key = "#{availability.available_entity_type}_#{availability.available_entity_id}"
        @availabilities[key] = availability
      end

      render partial: "manage/casting_availability/show_modal", locals: {
        show: @show,
        production: @production,
        cast_members: @cast_members,
        availabilities: @availabilities
      }
    end

    def update_show_availability
      @show = @production.shows.find(params[:id])

      # Update availabilities for each person and group
      params.each do |key, value|
        # Match pattern: availability_Person_123 or availability_Group_456
        next unless key.match?(/^availability_(Person|Group)_(\d+)$/)

        matches = key.match(/^availability_(Person|Group)_(\d+)$/)
        entity_type = matches[1]
        entity_id = matches[2].to_i

        # Find the entity (Person or Group)
        entity = if entity_type == "Person"
                   Person.find(entity_id)
        else
                   Group.find(entity_id)
        end

        availability = entity.show_availabilities.find_or_initialize_by(show: @show)

        if value == "available"
          availability.available!
        elsif value == "unavailable"
          availability.unavailable!
        end

        availability.save
      end

      respond_to do |format|
        format.html { redirect_to manage_production_casting_availability_index_path(@production), notice: "Availability updated" }
        format.json { render json: { success: true } }
      end
    end

    private

    def set_production
      unless Current.organization
        redirect_to select_organization_path, alert: "Please select an organization first."
        return
      end
      @production = Current.organization.productions.find(params.expect(:production_id))
      sync_current_production(@production)
    end
  end
end

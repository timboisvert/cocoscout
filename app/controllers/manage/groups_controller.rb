# frozen_string_literal: true

module Manage
  class GroupsController < Manage::ManageController
    before_action :set_group,
                  only: %i[show update_availability add_to_cast remove_from_cast remove_from_organization destroy]

    def show
      # Get all future shows for productions this group is a cast member of
      production_ids = @group.talent_pools.pluck(:production_id).uniq
      @shows = Show.where(production_id: production_ids, canceled: false)
                   .where("date_and_time >= ?", Time.current)
                   .order(:date_and_time)

      # Build a hash of availabilities: { show_id => show_availability }
      @availabilities = {}
      @group.show_availabilities.where(show: @shows).each do |availability|
        @availabilities[availability.show_id] = availability
      end

      # Check for edit mode
      @edit_mode = params[:edit] == "true"
    end

    def update_availability
      updated_count = 0

      # Loop through all parameters looking for availability_Group_* keys
      params.each do |key, value|
        next unless key.start_with?("availability_Group_")

        show_id = key.split("_").last.to_i
        show = Show.find(show_id)
        availability = @group.show_availabilities.find_or_initialize_by(show: show)

        # Only update if the status has changed
        new_status = value
        current_status = if availability.available?
                           "available"
        elsif availability.unavailable?
                           "unavailable"
        end

        next unless new_status != current_status

        case new_status
        when "available"
          availability.available!
        when "unavailable"
          availability.unavailable!
        end

        availability.save
        updated_count += 1
      end

      if updated_count.positive?
        redirect_to manage_group_path(@group),
                    notice: "Availability updated for #{updated_count} #{'show'.pluralize(updated_count)}"
      else
        redirect_to manage_group_path(@group), alert: "No availability changes were made"
      end
    end

    def add_to_cast
      if Current.production.blank?
        redirect_to manage_group_path(@group), alert: "Please select a production first"
        return
      end

      TalentPool.find_or_create_by(
        production: Current.production,
        entity: @group
      )

      redirect_to manage_group_path(@group), notice: "#{@group.name} added to #{Current.production.name}"
    end

    def remove_from_cast
      if Current.production.blank?
        redirect_to manage_group_path(@group), alert: "Please select a production first"
        return
      end

      talent_pool = TalentPool.find_by(
        production: Current.production,
        entity: @group
      )

      if talent_pool
        talent_pool.destroy
        redirect_to manage_group_path(@group), notice: "#{@group.name} removed from #{Current.production.name}"
      else
        redirect_to manage_group_path(@group), alert: "#{@group.name} was not in #{Current.production.name}"
      end
    end

    def remove_from_organization
      # Remove the group from the organization
      Current.organization.groups.delete(@group)

      redirect_to manage_directory_path, notice: "#{@group.name} was removed from #{Current.organization.name}",
                                         status: :see_other
    end

    def destroy
      @group.destroy
      redirect_to manage_directory_path, notice: "#{@group.name} was deleted", status: :see_other
    end

    private

    def set_group
      @group = Group.find(params[:id])
    end
  end
end

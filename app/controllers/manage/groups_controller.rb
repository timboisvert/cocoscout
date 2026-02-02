# frozen_string_literal: true

module Manage
  class GroupsController < Manage::ManageController
    before_action :set_group,
                  only: %i[show update update_availability availability_modal add_to_cast remove_from_cast remove_from_organization destroy]

    def show
      # Group detail view
    end

    def update_availability
      updated_count = 0
      last_status = nil
      current_status_for_response = nil

      # Loop through all parameters looking for availability_* keys
      params.each do |key, value|
        next unless key.start_with?("availability_") && key != "availability"

        show_id = key.split("_").last.to_i
        next if show_id.zero?

        show = Show.find_by(id: show_id)
        next unless show

        availability = @group.show_availabilities.find_or_initialize_by(show: show)

        # Only update if the status has changed
        new_status = value
        current_status = if availability.available?
                           "available"
        elsif availability.unavailable?
                           "unavailable"
        end

        # Track current status for response when no change is made
        current_status_for_response ||= current_status || new_status

        next unless new_status != current_status

        case new_status
        when "available"
          availability.available!
        when "unavailable"
          availability.unavailable!
        end

        availability.save
        updated_count += 1
        last_status = new_status
      end

      respond_to do |format|
        format.json do
          # Always return the current status - don't error if no changes made
          render json: { status: last_status || current_status_for_response }
        end
        format.html do
          if updated_count.positive?
            redirect_to manage_group_path(@group),
                        notice: "Availability updated for #{updated_count} #{'show'.pluralize(updated_count)}"
          else
            redirect_to manage_group_path(@group), alert: "No availability changes were made"
          end
        end
      end
    end

    # Returns HTML for member availability modal
    def availability_modal
      # Get all future shows for productions this group is a member of
      # via direct talent pools or shared talent pools
      direct_production_ids = TalentPool.joins(:talent_pool_memberships)
                                        .where(talent_pool_memberships: { member: @group })
                                        .pluck(:production_id)

      # Also get productions that share a talent pool this group is in
      shared_production_ids = TalentPoolShare.joins(talent_pool: :talent_pool_memberships)
                                             .where(talent_pool_memberships: { member: @group })
                                             .pluck(:production_id)

      production_ids = (direct_production_ids + shared_production_ids).uniq

      @shows = Show.where(production_id: production_ids, canceled: false)
                   .where("date_and_time >= ?", Time.current)
                   .includes(:production, :location)
                   .order(:date_and_time)

      # Build a hash of availabilities: { show_id => show_availability }
      @availabilities = {}
      @group.show_availabilities.where(show: @shows).each do |availability|
        @availabilities[availability.show_id] = availability
      end

      render partial: "manage/groups/availability_modal", locals: {
        member: @group,
        shows: @shows,
        availabilities: @availabilities,
        current_production_id: params[:production_id].to_s
      }
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

    def update
      if @group.update(group_params)
        redirect_to manage_group_path(@group), notice: "Notes updated successfully"
      else
        redirect_to manage_group_path(@group), alert: "Failed to update notes"
      end
    end

    private

    def set_group
      @group = Group.find(params[:id])
    end

    def group_params
      params.require(:group).permit(:producer_notes)
    end
  end
end

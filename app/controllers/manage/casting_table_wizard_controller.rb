# frozen_string_literal: true

module Manage
  class CastingTableWizardController < Manage::ManageController
    before_action :ensure_user_is_manager
    before_action :load_wizard_state

    # Step 1: Select Productions
    def productions
      # Exclude third-party productions as they don't have casting
      @productions = Current.user.accessible_productions.type_in_house.order(:name)
      @selected_production_ids = @wizard_state[:production_ids] || []
    end

    def save_productions
      production_ids = Array(params[:production_ids]).map(&:to_i).reject(&:zero?)

      if production_ids.empty?
        flash.now[:alert] = "Please select at least one production"
        @productions = Current.user.accessible_productions.type_in_house.order(:name)
        @selected_production_ids = []
        render :productions, status: :unprocessable_entity and return
      end

      # Verify all productions belong to this org and are not third-party
      valid_ids = Current.user.accessible_productions.type_in_house.where(id: production_ids).pluck(:id)
      if valid_ids.sort != production_ids.sort
        flash.now[:alert] = "Invalid production selection"
        @productions = Current.user.accessible_productions.type_in_house.order(:name)
        @selected_production_ids = []
        render :productions, status: :unprocessable_entity and return
      end

      @wizard_state[:production_ids] = production_ids
      save_wizard_state

      redirect_to manage_casting_tables_events_path
    end

    # Step 2: Select Events/Shows
    def events
      unless @wizard_state[:production_ids].present?
        redirect_to manage_casting_tables_new_path and return
      end

      @productions = Current.organization.productions.where(id: @wizard_state[:production_ids]).order(:name)
      @shows_by_production = {}
      @productions.each do |production|
        @shows_by_production[production.id] = production.shows
                                                         .where("date_and_time >= ?", Time.current)
                                                         .where(casting_enabled: true)
                                                         .order(:date_and_time)
      end

      @selected_show_ids = @wizard_state[:show_ids] || []

      # Check for shows already in finalized casting tables
      all_show_ids = @shows_by_production.values.flatten.map(&:id)
      @already_finalized_show_ids = CastingTable.shows_already_finalized(all_show_ids)
    end

    def save_events
      show_ids = Array(params[:show_ids]).map(&:to_i).reject(&:zero?)

      if show_ids.empty?
        flash.now[:alert] = "Please select at least one event"
        events # reload data
        render :events, status: :unprocessable_entity and return
      end

      # Verify shows belong to selected productions and org
      valid_ids = Show.joins(:production)
                      .where(production_id: @wizard_state[:production_ids])
                      .where(productions: { organization_id: Current.organization.id })
                      .where(id: show_ids)
                      .pluck(:id)

      if valid_ids.sort != show_ids.sort
        flash.now[:alert] = "Invalid event selection"
        events
        render :events, status: :unprocessable_entity and return
      end

      # Check if any are already finalized
      already_finalized = CastingTable.shows_already_finalized(show_ids)
      if already_finalized.any?
        flash.now[:alert] = "Some events have already been included in a finalized casting table"
        events
        render :events, status: :unprocessable_entity and return
      end

      @wizard_state[:show_ids] = show_ids
      save_wizard_state

      redirect_to manage_casting_tables_members_path
    end

    # Step 3: Select Members (from talent pools, or manually)
    def members
      unless @wizard_state[:show_ids].present?
        redirect_to manage_casting_tables_events_path and return
      end

      @productions = Current.organization.productions.where(id: @wizard_state[:production_ids])
      @member_source = @wizard_state[:member_source] || "talent_pool"
      @selected_member_ids = @wizard_state[:member_ids] || []

      # Get all talent pool members across selected productions
      @talent_pool_people = Person.joins(talent_pool_memberships: :talent_pool)
                                   .where(talent_pools: { production_id: @wizard_state[:production_ids] })
                                   .includes(profile_headshots: { image_attachment: :blob })
                                   .distinct
                                   .order(:name)

      @talent_pool_groups = Group.joins(talent_pool_memberships: :talent_pool)
                                  .where(talent_pools: { production_id: @wizard_state[:production_ids] })
                                  .includes(profile_headshots: { image_attachment: :blob })
                                  .distinct
                                  .order(:name)
    end

    def save_members
      member_source = params[:member_source] || "talent_pool"

      if member_source == "talent_pool"
        # Use all talent pool members
        person_ids = Person.joins(talent_pool_memberships: :talent_pool)
                           .where(talent_pools: { production_id: @wizard_state[:production_ids] })
                           .distinct.pluck(:id)
        group_ids = Group.joins(talent_pool_memberships: :talent_pool)
                         .where(talent_pools: { production_id: @wizard_state[:production_ids] })
                         .distinct.pluck(:id)

        @wizard_state[:member_source] = "talent_pool"
        @wizard_state[:person_ids] = person_ids
        @wizard_state[:group_ids] = group_ids
      else
        # Manual selection
        person_ids = Array(params[:person_ids]).map(&:to_i).reject(&:zero?)
        group_ids = Array(params[:group_ids]).map(&:to_i).reject(&:zero?)

        if person_ids.empty? && group_ids.empty?
          flash.now[:alert] = "Please select at least one person or group"
          members
          render :members, status: :unprocessable_entity and return
        end

        @wizard_state[:member_source] = "manual"
        @wizard_state[:person_ids] = person_ids
        @wizard_state[:group_ids] = group_ids
      end

      save_wizard_state
      redirect_to manage_casting_tables_review_path
    end

    # Step 4: Review and Create
    def review
      unless @wizard_state[:person_ids].present? || @wizard_state[:group_ids].present?
        redirect_to manage_casting_tables_members_path and return
      end

      @productions = Current.organization.productions.where(id: @wizard_state[:production_ids]).order(:name)
      @shows = Show.where(id: @wizard_state[:show_ids]).order(:date_and_time)
      @people = Person.where(id: @wizard_state[:person_ids]).order(:name)
      @groups = Group.where(id: @wizard_state[:group_ids]).order(:name)

      @default_name = generate_default_name
    end

    def create_table
      name = params[:name].presence || generate_default_name

      casting_table = CastingTable.new(
        organization: Current.organization,
        created_by: Current.user,
        name: name,
        status: "draft"
      )

      CastingTable.transaction do
        casting_table.save!

        # Add productions
        @wizard_state[:production_ids].each do |production_id|
          casting_table.casting_table_productions.create!(production_id: production_id)
        end

        # Add events
        @wizard_state[:show_ids].each do |show_id|
          casting_table.casting_table_events.create!(show_id: show_id)
        end

        # Add members
        @wizard_state[:person_ids]&.each do |person_id|
          casting_table.casting_table_members.create!(memberable_type: "Person", memberable_id: person_id)
        end
        @wizard_state[:group_ids]&.each do |group_id|
          casting_table.casting_table_members.create!(memberable_type: "Group", memberable_id: group_id)
        end
      end

      clear_wizard_state
      redirect_to manage_casting_table_path(casting_table), notice: "Casting table created! Start assigning roles."

    rescue ActiveRecord::RecordInvalid => e
      flash.now[:alert] = "Error creating casting table: #{e.message}"
      review
      render :review, status: :unprocessable_entity
    end

    def cancel
      clear_wizard_state
      redirect_to manage_casting_tables_path, notice: "Casting table creation cancelled"
    end

    private

    def load_wizard_state
      @wizard_state = (session[:casting_table_wizard] || {}).with_indifferent_access
    end

    def save_wizard_state
      session[:casting_table_wizard] = @wizard_state.to_h
    end

    def clear_wizard_state
      session.delete(:casting_table_wizard)
    end

    def generate_default_name
      productions = Current.organization.productions.where(id: @wizard_state[:production_ids])
      shows = Show.where(id: @wizard_state[:show_ids]).order(:date_and_time)

      # Build production names portion
      production_names = if productions.count == 1
        productions.first.name
      elsif productions.count <= 3
        productions.pluck(:name).join(", ")
      else
        "#{productions.count} Productions"
      end

      # Build date range portion
      date_range = if shows.any?
        first_date = shows.first.date_and_time
        last_date = shows.last.date_and_time
        if first_date.to_date == last_date.to_date
          first_date.strftime("%b %-d")
        elsif first_date.month == last_date.month && first_date.year == last_date.year
          "#{first_date.strftime('%b %-d')}-#{last_date.strftime('%-d')}"
        else
          "#{first_date.strftime('%b %-d')} - #{last_date.strftime('%b %-d')}"
        end
      else
        Date.today.strftime("%B %Y")
      end

      # Build event count portion
      event_count = shows.count
      event_text = event_count == 1 ? "1 event" : "#{event_count} events"

      "#{production_names} (#{date_range}, #{event_text})"
    end
  end
end

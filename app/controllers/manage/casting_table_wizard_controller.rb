# frozen_string_literal: true

module Manage
  class CastingTableWizardController < Manage::ManageController
    before_action :ensure_user_is_manager
    before_action :load_wizard_state
    before_action :set_wizard_steps

    # Step 1: Select Productions
    def productions
      # Exclude third-party productions as they don't have casting
      @productions = Current.user.accessible_productions.castable.order(:name)

      # With exactly one castable production there is nothing to pick — seed
      # the wizard state and jump straight to the events step.
      if @productions.one?
        @wizard_state[:production_ids] = [ @productions.first.id ]
        save_wizard_state
        redirect_to manage_casting_tables_events_path and return
      end

      @selected_production_ids = @wizard_state[:production_ids] || []
    end

    def save_productions
      production_ids = Array(params[:production_ids]).map(&:to_i).reject(&:zero?)

      if production_ids.empty?
        flash.now[:alert] = "Please select at least one production"
        @productions = Current.user.accessible_productions.castable.order(:name)
        @selected_production_ids = []
        render :productions, status: :unprocessable_entity and return
      end

      # Verify all productions belong to this org and are not third-party
      valid_ids = Current.user.accessible_productions.castable.where(id: production_ids).pluck(:id)
      if valid_ids.sort != production_ids.sort
        flash.now[:alert] = "Invalid production selection"
        @productions = Current.user.accessible_productions.castable.order(:name)
        @selected_production_ids = []
        render :productions, status: :unprocessable_entity and return
      end

      @wizard_state[:production_ids] = production_ids
      save_wizard_state

      redirect_to manage_casting_tables_events_path
    end

    # Step 2: Select Events/Shows
    def events
      return redirect_to(manage_casting_tables_new_path) if @wizard_state[:production_ids].blank?

      load_events_data
    end

    def save_events
      # The step's own guard, up front. The re-render paths below call
      # load_events_data, which only loads — an earlier version called #events,
      # and on an expired session that redirected and then rendered, so a stale
      # tab got a DoubleRenderError instead of being sent back to step one.
      return redirect_to(manage_casting_tables_new_path) if @wizard_state[:production_ids].blank?

      show_ids = Array(params[:show_ids]).map(&:to_i).reject(&:zero?)

      if show_ids.empty?
        flash.now[:alert] = "Please select at least one event"
        load_events_data
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
        load_events_data
        render :events, status: :unprocessable_entity and return
      end

      # Check if any are already finalized
      already_finalized = CastingTable.shows_already_finalized(show_ids)
      if already_finalized.any?
        flash.now[:alert] = "Some events have already been included in a finalized casting table"
        load_events_data
        render :events, status: :unprocessable_entity and return
      end

      @wizard_state[:show_ids] = show_ids
      save_wizard_state

      redirect_to manage_casting_tables_members_path
    end

    # Step 3: Select Members (from talent pools, or manually)
    def members
      return redirect_to(manage_casting_tables_new_path) if @wizard_state[:production_ids].blank?
      return redirect_to(manage_casting_tables_events_path) if @wizard_state[:show_ids].blank?

      load_members_data
    end

    def save_members
      # Without productions there's no pool to read and nothing to name, so the
      # only honest answer is to start again rather than show an empty step.
      return redirect_to(manage_casting_tables_new_path) if @wizard_state[:production_ids].blank?
      return redirect_to(manage_casting_tables_events_path) if @wizard_state[:show_ids].blank?

      member_source = params[:member_source] || "talent_pool"

      if member_source == "talent_pool"
        ids = talent_pool_member_ids
        person_ids = ids[:person_ids]
        group_ids = ids[:group_ids]

        # An empty pool used to sail through to the review step, which bounced
        # straight back here for having nobody to review — so Next looked like it
        # did nothing at all. Say what's wrong instead.
        if person_ids.empty? && group_ids.empty?
          flash.now[:alert] = "There's nobody in the talent pool for #{selected_productions.map(&:name).to_sentence}. " \
                              "Add people to the pool, or choose them by hand below."
          load_members_data
          render :members, status: :unprocessable_entity and return
        end

        @wizard_state[:member_source] = "talent_pool"
        @wizard_state[:person_ids] = person_ids
        @wizard_state[:group_ids] = group_ids
      else
        # Manual selection
        person_ids = Array(params[:person_ids]).map(&:to_i).reject(&:zero?)
        group_ids = Array(params[:group_ids]).map(&:to_i).reject(&:zero?)

        if person_ids.empty? && group_ids.empty?
          flash.now[:alert] = "Please select at least one person or group"
          load_members_data
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
      if @wizard_state[:person_ids].blank? && @wizard_state[:group_ids].blank?
        return redirect_to(manage_casting_tables_members_path)
      end

      load_review_data
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
      load_review_data
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

    def load_events_data
      @productions = selected_productions
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

    def load_members_data
      @productions = selected_productions
      @member_source = @wizard_state[:member_source] || "talent_pool"
      @selected_person_ids = Array(@wizard_state[:person_ids]).map(&:to_i)
      @selected_group_ids = Array(@wizard_state[:group_ids]).map(&:to_i)

      ids = talent_pool_member_ids
      @talent_pool_people = Person.where(id: ids[:person_ids])
                                  .includes(profile_headshots: { image_attachment: :blob })
                                  .order(:name)
      @talent_pool_groups = Group.where(id: ids[:group_ids])
                                  .includes(profile_headshots: { image_attachment: :blob })
                                  .order(:name)
    end


    def load_review_data
      @productions = selected_productions
      @shows = Show.where(id: @wizard_state[:show_ids]).order(:date_and_time)
      @people = Person.where(id: @wizard_state[:person_ids]).order(:name)
      @groups = Group.where(id: @wizard_state[:group_ids]).order(:name)
      @default_name = generate_default_name
    end

    def selected_productions
      @selected_productions ||= Current.organization.productions
                                       .where(id: @wizard_state[:production_ids])
                                       .order(:name).to_a
    end

    # Everyone in the EFFECTIVE talent pool of every selected production.
    #
    # Resolved through Production#effective_talent_pool rather than by querying
    # talent_pools.production_id: a production may be using another production's
    # shared pool, and on an org in single-pool mode the one pool belongs to
    # whichever production owns it. Neither case has a talent_pool whose
    # production_id is the selected production, so the raw query found nobody and
    # the wizard dead-ended.
    def talent_pool_member_ids
      pool_ids = selected_productions.filter_map { |p| p.effective_talent_pool&.id }.uniq
      return { person_ids: [], group_ids: [] } if pool_ids.empty?

      memberships = TalentPoolMembership.where(talent_pool_id: pool_ids)
      {
        person_ids: memberships.where(member_type: "Person").distinct.pluck(:member_id),
        group_ids: memberships.where(member_type: "Group").distinct.pluck(:member_id)
      }
    end

    # Step bar for every wizard view. With one castable production the picker
    # step is skipped (see #productions), so it shouldn't appear as a step.
    def set_wizard_steps
      @wizard_steps = [ { name: "Productions" }, { name: "Events" }, { name: "Members" }, { name: "Review" } ]
      @wizard_steps.shift if Current.user.accessible_productions.castable.one?
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

# frozen_string_literal: true

module Manage
  # Set up casting for a production, step by step (Tim, 2026-11-18): who is
  # cast, roles or acts, the roles, which dates are cast, then a review.
  # It starts from the "Not set up" panel on the production's casting board,
  # for a production people are cast in that has no roles and has never been
  # set up (Production#casting_state). Once it's done, changes happen in
  # Casting Settings.
  #
  # The first three steps are the new-production wizard's own
  # (Manage::CastingSteps, manage/casting_steps). Nothing is changed on the
  # production until Finish: the answers wait in the cache, as that wizard's
  # do.
  class CastingSetupController < Manage::ManageController
    include Manage::CastingSteps

    STEPS = %i[who style roles dates review].freeze

    before_action :set_production
    before_action :check_production_access
    before_action :ensure_user_is_manager
    before_action :ensure_setup_applies
    before_action :load_wizard_state
    before_action :load_dates, only: %i[dates save_dates review finish]

    # Step 1: who you cast
    def who
      @wizard_state[:casting_source] ||= (@production.casting_manual? ? "manual" : "talent_pool")
    end

    def save_who
      source = params[:casting_source].to_s
      @wizard_state[:casting_source] = source == "manual" ? "manual" : "talent_pool"
      save_wizard_state
      redirect_to manage_casting_setup_style_path(@production)
    end

    # Step 2: roles or acts
    def style
      @wizard_state[:casting_mode] ||= @production.casting_mode
    end

    def save_style
      store_casting_style(params[:casting_mode])
      save_wizard_state
      redirect_to manage_casting_setup_roles_path(@production)
    end

    # Step 3: your roles (the default lineup, when casting by acts)
    def roles
      @wizard_state[:roles] ||= []
    end

    def save_roles
      store_roles(params[:has_roles], params[:roles])
      save_wizard_state
      redirect_to manage_casting_setup_dates_path(@production)
    end

    # Step 4: which dates are cast (all performances, by event type, or
    # specific dates: the choice Ticketing offers for which dates it sells)
    def dates
      @picked = picked_date_ids
    end

    def save_dates
      matching = params[:matching].to_s
      @wizard_state[:date_matching] = Production::CASTING_EVENT_MATCHING.include?(matching) ? matching : "all"
      @wizard_state[:date_event_types] = Array(params[:event_types]).map(&:to_s) & EventTypes.all
      @wizard_state[:date_ids] = Array(params[:show_ids]).map(&:to_i) & @dates.map(&:id)
      save_wizard_state
      redirect_to manage_casting_setup_review_path(@production)
    end

    # Step 5: review
    def review
      load_review
    end

    def finish
      Production.transaction do
        @production.update!(casting_source: wizard_casting_source, casting_mode: wizard_casting_mode, casting_setup_completed: true)
        create_wizard_roles!(@production)
        CastingAnswer.choose_rule!(@production, matching: wizard_date_matching, event_types: @wizard_state[:date_event_types], show_ids: picked_date_ids)
      end
      clear_wizard_state
      redirect_to manage_casting_production_path(@production), notice: "Casting is set up for #{@production.name}."
    rescue ActiveRecord::RecordInvalid => e
      load_review
      flash.now[:alert] = e.message
      render :review, status: :unprocessable_content
    end

    def cancel
      clear_wizard_state
      redirect_to manage_casting_production_path(@production), notice: "Nothing was changed."
    end

    private

    def set_production
      unless Current.organization
        redirect_to select_organization_path, alert: "Please select an organization first."
        return
      end
      @production = Current.organization.productions.find(params.require(:production_id))
      sync_current_production(@production)
    end

    # Set-up is for a production people are cast in that isn't set up yet.
    # Anything else has a truer place to go.
    def ensure_setup_applies
      if !@production.castable?
        redirect_to manage_production_path(@production), alert: "Casting isn't available for this production."
      elsif @production.casting_state == :off
        redirect_to manage_casting_settings_path(@production),
                    notice: "We don't cast people in #{@production.name}. Change that here, and then you can set up casting."
      elsif @production.casting_state == :on
        redirect_to manage_casting_settings_path(@production),
                    notice: "Casting is already set up for #{@production.name}. You can change it here."
      end
    end

    # The coming dates and who they're booked with, for the Dates step.
    def load_dates
      @dates = CastingAnswer.upcoming(@production).includes(:location, :location_space, linked_show: { production: :organization }).to_a
      @cast_ids = CastingAnswer.cast_show_ids(@production).to_set
    end

    # The Dates step's choice so far: "all" until it's answered.
    def wizard_date_matching
      @wizard_state[:date_matching].to_s.presence_in(Production::CASTING_EVENT_MATCHING) || "all"
    end
    helper_method :wizard_date_matching

    # The dates ticked under "Specific dates"; before the step has been
    # answered, the ones that have casting on today or anybody cast in them.
    def picked_date_ids
      if @wizard_state.key?(:date_ids)
        Array(@wizard_state[:date_ids]).map(&:to_i) & @dates.map(&:id)
      else
        @dates.select { |show| show.casting_enabled? || @cast_ids.include?(show.id) }.map(&:id)
      end
    end

    # What Review says about the dates: the choice as it would be saved
    # (held on the production in memory only), and the coming dates it
    # covers.
    def load_review
      @production.assign_attributes(casting_event_matching: wizard_date_matching,
                                    casting_event_type_filter: wizard_date_matching == "event_types" ? Array(@wizard_state[:date_event_types]) : [])
      @covered = CastingAnswer.covered_ids(@production, @dates, picked_date_ids)
    end

    def load_wizard_state
      @wizard_state = (Rails.cache.read(wizard_cache_key) || {}).with_indifferent_access
    end

    def save_wizard_state
      Rails.cache.write(wizard_cache_key, @wizard_state.to_h, expires_in: 24.hours)
    end

    def clear_wizard_state
      Rails.cache.delete(wizard_cache_key)
    end

    def wizard_cache_key
      "casting_setup:#{Current.user.id}:#{@production.id}"
    end

    # The step bar: every step that has been reached is a link back.
    def setup_steps
      [
        { key: :who, name: "Who you cast", path: manage_casting_setup_path(@production) },
        { key: :style, name: "Roles or acts", path: manage_casting_setup_style_path(@production) },
        { key: :roles, name: (act_based_wizard? ? "Your lineup" : "Your roles"), path: manage_casting_setup_roles_path(@production) },
        { key: :dates, name: "Dates", path: manage_casting_setup_dates_path(@production) },
        { key: :review, name: "Review", path: manage_casting_setup_review_path(@production) }
      ]
    end
    helper_method :setup_steps
  end
end

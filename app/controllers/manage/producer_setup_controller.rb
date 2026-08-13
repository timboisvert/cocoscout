# frozen_string_literal: true

module Manage
  # Combined first-run setup for a brand-new producer: what are you creating
  # (genre) -> name it -> pick a plan. Creates the Organization and its first
  # Production together from one name, so a producer-tier user never has to
  # learn what an "organization" is. Users who already belong to a (non-demo)
  # organization are sent to the normal flows instead.
  class ProducerSetupController < Manage::ManageController
    before_action :ensure_first_run
    before_action :load_setup_state
    before_action :hide_sidebar

    # Step 1: What are you creating?
    def genre
      capture_plan_params
      # SketchFest arrivals are sketch teams until they say otherwise.
      @setup_state[:genre] ||= "sketch" if referred_from_sketchfest?
    end

    def save_genre
      genre = params[:genre].to_s
      unless ProductionGenres.keys.include?(genre)
        flash.now[:alert] = "Pick what you're creating to continue"
        render :genre, status: :unprocessable_entity and return
      end

      @setup_state[:genre] = genre
      save_setup_state
      redirect_to manage_producer_setup_name_path
    end

    # Step 2: What's it called?
    def name
      redirect_to manage_producer_setup_path and return if @setup_state[:genre].blank?
    end

    def save_name
      @setup_state[:name] = params[:name]&.strip

      if @setup_state[:name].blank?
        flash.now[:alert] = "Please enter a name"
        render :name, status: :unprocessable_entity and return
      end

      save_setup_state
      redirect_to manage_producer_setup_plan_path
    end

    # Step 3: Pick a plan (Producer free vs Pro, both intervals).
    def plan
      redirect_to manage_producer_setup_path and return if @setup_state[:name].blank?
    end

    def complete
      if @setup_state[:genre].blank? || @setup_state[:name].blank?
        redirect_to manage_producer_setup_path,
                    alert: "Your setup session expired — it only takes a minute to start again." and return
      end

      chosen_plan = params[:plan] == "pro" ? "pro" : "free"
      interval = SignupTracking::PLAN_INTERVALS.include?(params[:interval]) ? params[:interval] : "year"

      ActiveRecord::Base.transaction do
        # One name for both: the organization stays invisible scaffolding until
        # the user grows into needing it (a second production, a team, billing).
        @organization = Organization.new(name: @setup_state[:name], owner: Current.user)
        # Campaign attribution — from the session on purpose, so a crafted form
        # post can't fake it (same rule as Manage::OrganizationsController).
        @organization.referral_source = session[:referral_source]
        @organization.save!

        OrganizationRole.create!(user: Current.user, organization: @organization, company_role: "manager")
        ensure_person_in_organization!(@organization)

        @production = @organization.productions.new(
          name: @setup_state[:name],
          genre: @setup_state[:genre],
          casting_source: "talent_pool",
          casting_setup_completed: true
        )
        @production.save!
      end

      clear_setup_state

      # Make the new org/production current, mirroring the production wizard.
      session[:current_organization_id] ||= {}
      session[:current_organization_id][Current.user.id.to_s] = @organization.id
      session[:current_production_id_for_organization] ||= {}
      session[:current_production_id_for_organization]["#{Current.user.id}_#{@organization.id}"] = @production.id

      # They've produced — the Start Producing welcome has nothing left to teach.
      Current.user.update(welcomed_production_at: Time.current) if Current.user.welcomed_production_at.nil?
      # Turn on the "here's what to do next" panel on the manage home page.
      Current.user.activate_guide!(:production_next_steps)

      if chosen_plan == "pro"
        # Straight into Stripe checkout; the org stays on the free tier until
        # Stripe confirms the subscription. Land on home afterwards so the
        # what's-next panel greets them, not the billing tab.
        session[:return_to_home_after_checkout] = true
        redirect_to manage_billing_path(upgrade: interval)
      else
        redirect_to_intent_or(manage_path, notice: "#{@production.name} is ready!")
      end
    rescue ActiveRecord::RecordInvalid => e
      flash.now[:alert] = e.record.errors.full_messages.to_sentence.presence || e.message
      render :plan, status: :unprocessable_entity
    end

    def cancel
      clear_setup_state
      redirect_to manage_path
    end

    private

    # No org exists yet, so the manage sidebar has nothing to show (same
    # treatment as the Start Producing welcome).
    def hide_sidebar
      @show_manage_sidebar = false
    end

    # This flow is exclusively for first-run producers. Anyone who already has
    # a real (non-demo) organization uses the org picker and production wizard.
    def ensure_first_run
      return if Current.user.accessible_organizations.non_demo.none?

      redirect_to manage_path
    end

    def load_setup_state
      @setup_state = (Rails.cache.read(setup_cache_key) || {}).with_indifferent_access
    end

    def save_setup_state
      Rails.cache.write(setup_cache_key, @setup_state.to_h, expires_in: 24.hours)
    end

    def clear_setup_state
      Rails.cache.delete(setup_cache_key)
    end

    # Keyed by user alone — unlike the production wizard, there is no
    # organization yet.
    def setup_cache_key
      "producer_setup:#{Current.user.id}"
    end

    # A "Go Pro" CTA's plan choice arrives as allowlisted query params (the
    # session keys were consumed at the post-signup landing). Remember them so
    # the plan step can preselect Pro.
    def capture_plan_params
      return unless SignupTracking::SIGNUP_PLANS.include?(params[:plan].to_s)

      @setup_state[:preselect_plan] = params[:plan].to_s
      @setup_state[:preselect_interval] =
        SignupTracking::PLAN_INTERVALS.include?(params[:interval].to_s) ? params[:interval].to_s : "year"
      save_setup_state
    end

    def referred_from_sketchfest?
      session[:referral_source] == "sketchfest"
    end
  end
end

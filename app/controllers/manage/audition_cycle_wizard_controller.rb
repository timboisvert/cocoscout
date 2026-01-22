# frozen_string_literal: true

module Manage
  class AuditionCycleWizardController < Manage::ManageController
    before_action :set_production, except: [ :select_production, :save_production_selection ]
    before_action :check_production_access, except: [ :select_production, :save_production_selection ]
    before_action :ensure_user_is_manager
    before_action :load_wizard_state, except: [ :select_production, :save_production_selection ]

    # Step 0: Select Production (when entering from org-level)
    def select_production
      @productions = Current.organization.productions.order(:name)
    end

    def save_production_selection
      production_id = params[:production_id]

      if production_id.blank?
        flash.now[:alert] = "Please select a production"
        @productions = Current.organization.productions.order(:name)
        render :select_production, status: :unprocessable_entity and return
      end

      production = Current.organization.productions.find_by(id: production_id)
      unless production
        flash.now[:alert] = "Production not found"
        @productions = Current.organization.productions.order(:name)
        render :select_production, status: :unprocessable_entity and return
      end

      # Redirect to the production-level wizard
      redirect_to manage_signups_auditions_wizard_path(production)
    end

    # Step 1: Audition Format
    def format
      # Initial step - choose video, in-person, or both
    end

    def save_format
      @wizard_state[:allow_video_submissions] = params[:allow_video_submissions] == "1"
      @wizard_state[:allow_in_person_auditions] = params[:allow_in_person_auditions] == "1"

      unless @wizard_state[:allow_video_submissions] || @wizard_state[:allow_in_person_auditions]
        flash.now[:alert] = "Please select at least one audition format"
        render :format, status: :unprocessable_entity and return
      end

      save_wizard_state
      redirect_to manage_signups_auditions_wizard_schedule_path(@production)
    end

    # Step 2: Sign-up Window
    def schedule
      @wizard_state[:opens_at] ||= Time.current.beginning_of_day
      @wizard_state[:closes_at] ||= 2.weeks.from_now.end_of_day
    end

    def save_schedule
      @wizard_state[:opens_at] = params[:opens_at]
      @wizard_state[:closes_at] = params[:closes_at].presence

      if @wizard_state[:opens_at].blank?
        flash.now[:alert] = "Please set an opening date"
        render :schedule, status: :unprocessable_entity and return
      end

      save_wizard_state

      # If in-person auditions are enabled, go to sessions step, otherwise skip to availability
      if @wizard_state[:allow_in_person_auditions]
        redirect_to manage_signups_auditions_wizard_sessions_path(@production)
      else
        redirect_to manage_signups_auditions_wizard_availability_path(@production)
      end
    end

    # Step 3: Audition Sessions (only for in-person auditions)
    def sessions
      # Redirect if in-person auditions not enabled
      unless @wizard_state[:allow_in_person_auditions]
        redirect_to manage_signups_auditions_wizard_availability_path(@production)
        return
      end

      @locations = @production.organization.locations.order(:name)
      @wizard_state[:audition_sessions] ||= []
    end

    def save_sessions
      # Just move to next step - sessions are already saved in wizard state
      save_wizard_state
      redirect_to manage_signups_auditions_wizard_availability_path(@production)
    end

    def generate_sessions
      count = params[:session_count].to_i
      duration = params[:session_duration].to_i
      start_at = params[:start_at]
      location_id = params[:location_id]

      if count <= 0 || count > 20
        flash.now[:alert] = "Please enter a valid number of sessions (1-20)"
        @locations = @production.organization.locations.order(:name)
        render :sessions, status: :unprocessable_entity and return
      end

      if duration <= 0
        flash.now[:alert] = "Please enter a valid session duration"
        @locations = @production.organization.locations.order(:name)
        render :sessions, status: :unprocessable_entity and return
      end

      if start_at.blank?
        flash.now[:alert] = "Please select a start date/time"
        @locations = @production.organization.locations.order(:name)
        render :sessions, status: :unprocessable_entity and return
      end

      if location_id.blank?
        flash.now[:alert] = "Please select a location"
        @locations = @production.organization.locations.order(:name)
        render :sessions, status: :unprocessable_entity and return
      end

      # Generate sessions
      @wizard_state[:audition_sessions] ||= []
      current_time = Time.parse(start_at)

      count.times do |i|
        @wizard_state[:audition_sessions] << {
          start_at: current_time.iso8601,
          duration_minutes: duration,
          location_id: location_id
        }
        current_time += duration.minutes
      end

      save_wizard_state
      redirect_to manage_signups_auditions_wizard_sessions_path(@production), notice: "#{count} sessions generated"
    end

    def add_session
      start_at = params[:start_at]
      duration = params[:duration_minutes].to_i
      location_id = params[:location_id]

      if start_at.blank? || duration <= 0 || location_id.blank?
        flash[:alert] = "Please fill in all session details"
        redirect_to manage_signups_auditions_wizard_sessions_path(@production) and return
      end

      @wizard_state[:audition_sessions] ||= []
      @wizard_state[:audition_sessions] << {
        start_at: Time.parse(start_at).iso8601,
        duration_minutes: duration,
        location_id: location_id
      }

      save_wizard_state
      redirect_to manage_signups_auditions_wizard_sessions_path(@production), notice: "Session added"
    end

    def update_session
      index = params[:session_index].to_i
      session_data = @wizard_state[:audition_sessions][index]

      if session_data
        session_data[:start_at] = Time.parse(params[:start_at]).iso8601 if params[:start_at].present?
        session_data[:duration_minutes] = params[:duration_minutes].to_i if params[:duration_minutes].present?
        session_data[:location_id] = params[:location_id] if params[:location_id].present?
        save_wizard_state
      end

      redirect_to manage_signups_auditions_wizard_sessions_path(@production), notice: "Session updated"
    end

    def delete_session
      index = params[:session_index].to_i
      @wizard_state[:audition_sessions]&.delete_at(index)
      save_wizard_state
      redirect_to manage_signups_auditions_wizard_sessions_path(@production), notice: "Session removed"
    end

    # Step 4: Availability Requirements
    def availability
      @shows = @production.shows.where(canceled: false)
                          .where("date_and_time >= ?", Time.current)
                          .order(:date_and_time)
                          .limit(50)
    end

    def save_availability
      @wizard_state[:include_availability_section] = params[:include_availability_section] == "1"
      @wizard_state[:require_all_availability] = params[:require_all_availability] == "1"
      @wizard_state[:availability_show_ids] = params[:availability_show_ids] || []

      @wizard_state[:include_audition_availability_section] = params[:include_audition_availability_section] == "1"
      @wizard_state[:require_all_audition_availability] = params[:require_all_audition_availability] == "1"

      save_wizard_state
      redirect_to manage_signups_auditions_wizard_reviewers_path(@production)
    end

    # Step 4: Reviewer Team
    def reviewers
      @people = @production.effective_talent_pool&.people&.order(:name) || []
      @selected_reviewer_ids = @wizard_state[:reviewer_person_ids] || []

      # Get managers (global + production team)
      global_managers = Current.organization.organization_roles.where(company_role: %w[manager viewer]).includes(user: :default_person).map { |r| { user: r.user, role: "#{r.company_role.capitalize} (Global)" } }
      production_team = @production.production_permissions.where(role: %w[manager viewer]).includes(user: :default_person).map { |p| { user: p.user, role: p.role.capitalize } }
      @managers = (global_managers + production_team).uniq { |t| t[:user].id }

      # Get talent pool people
      @talent_pool_people = @production.effective_talent_pool&.people&.order(:name) || []
    end

    def save_reviewers
      @wizard_state[:reviewer_access_type] = params[:reviewer_access_type] || "managers"
      @wizard_state[:reviewer_person_ids] = params[:reviewer_person_ids] || []

      save_wizard_state
      redirect_to manage_signups_auditions_wizard_voting_path(@production)
    end

    # Step 5: Voting
    def voting
    end

    def save_voting
      @wizard_state[:voting_enabled] = params[:voting_enabled] == "1"
      @wizard_state[:audition_voting_enabled] = params[:audition_voting_enabled] == "1"

      save_wizard_state
      redirect_to manage_signups_auditions_wizard_review_path(@production)
    end

    # Step 6: Review & Create
    def review
      # Show summary of all settings before creating
    end

    def create_cycle
      @audition_cycle = AuditionCycle.new(
        production: @production,
        active: true,
        allow_video_submissions: @wizard_state[:allow_video_submissions],
        allow_in_person_auditions: @wizard_state[:allow_in_person_auditions],
        opens_at: @wizard_state[:opens_at],
        closes_at: @wizard_state[:closes_at],
        include_availability_section: @wizard_state[:include_availability_section],
        require_all_availability: @wizard_state[:require_all_availability],
        availability_show_ids: @wizard_state[:availability_show_ids],
        include_audition_availability_section: @wizard_state[:include_audition_availability_section],
        require_all_audition_availability: @wizard_state[:require_all_audition_availability],
        reviewer_access_type: @wizard_state[:reviewer_access_type] || "managers",
        voting_enabled: @wizard_state[:voting_enabled].nil? ? true : @wizard_state[:voting_enabled],
        audition_voting_enabled: @wizard_state[:audition_voting_enabled].nil? ? true : @wizard_state[:audition_voting_enabled]
      )

      # Set the audition_type for backward compatibility
      if @wizard_state[:allow_video_submissions] && !@wizard_state[:allow_in_person_auditions]
        @audition_cycle.audition_type = :video_upload
      else
        @audition_cycle.audition_type = :in_person
      end

      # Generate unique token using ShortKeyService
      @audition_cycle.token = ShortKeyService.generate(type: :audition)

      ActiveRecord::Base.transaction do
        # Deactivate other active cycles for this production
        @production.audition_cycles.where(active: true).update_all(active: false)

        if @audition_cycle.save
          # Create reviewer assignments if specific reviewers were selected
          if @wizard_state[:reviewer_access_type] == "specific" && @wizard_state[:reviewer_person_ids].present?
            @wizard_state[:reviewer_person_ids].each do |person_id|
              @audition_cycle.audition_reviewers.create(person_id: person_id)
            end
          end

          # Create audition sessions if in-person auditions are enabled
          if @wizard_state[:allow_in_person_auditions] && @wizard_state[:audition_sessions].present?
            @wizard_state[:audition_sessions].each do |session_data|
              @audition_cycle.audition_sessions.create!(
                start_at: Time.parse(session_data[:start_at]),
                location_id: session_data[:location_id]
              )
            end
          end

          # Clear wizard state
          clear_wizard_state

          redirect_to manage_form_signups_auditions_cycle_path(@production, @audition_cycle),
                      notice: "Audition cycle created! Now customize your sign-up form."
        else
          flash.now[:alert] = @audition_cycle.errors.full_messages.to_sentence
          render :review, status: :unprocessable_entity
        end
      end
    end

    # Cancel wizard and clear state
    def cancel
      clear_wizard_state
      redirect_to manage_signups_auditions_path(@production)
    end

    private

    def set_production
      unless Current.organization
        redirect_to select_organization_path, alert: "Please select an organization first."
        return
      end
      @production = Current.organization.productions.find(params[:production_id])
      sync_current_production(@production)
    end

    def load_wizard_state
      session[:audition_wizard] ||= {}
      session[:audition_wizard][@production.id.to_s] ||= {}
      @wizard_state = session[:audition_wizard][@production.id.to_s].with_indifferent_access
    end

    def save_wizard_state
      session[:audition_wizard][@production.id.to_s] = @wizard_state.to_h
    end

    def clear_wizard_state
      session[:audition_wizard]&.delete(@production.id.to_s)
    end
  end
end

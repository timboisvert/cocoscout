# frozen_string_literal: true

module Manage
  class AuditionCycleWizardController < Manage::ManageController
    before_action :set_production, except: [ :select_production, :save_production_selection ]
    before_action :check_production_access, except: [ :select_production, :save_production_selection ]
    before_action :ensure_user_is_manager
    before_action :load_wizard_state, except: [ :select_production, :save_production_selection ]

    # Step 0: Select Production (when entering from org-level)
    def select_production
      # Exclude third-party productions as they don't have casting
      @productions = Current.user.accessible_productions.castable.order(:name)
    end

    def save_production_selection
      production_id = params[:production_id]

      if production_id.blank?
        flash.now[:alert] = "Please select a production"
        @productions = Current.user.accessible_productions.castable.order(:name)
        render :select_production, status: :unprocessable_entity and return
      end

      # Only allow in-house productions for audition cycles
      production = Current.user.accessible_productions.castable.find_by(id: production_id)
      unless production
        flash.now[:alert] = "Production not found"
        @productions = Current.user.accessible_productions.castable.order(:name)
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
      @wizard_state[:listed_in_directory] = params[:listed_in_directory] == "1"

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
      is_online = ActiveModel::Type::Boolean.new.cast(params[:is_online])
      location_id = is_online ? nil : params[:location_id]
      online_location_info = is_online ? params[:online_location_info].presence : nil

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

      if !is_online && location_id.blank?
        flash.now[:alert] = "Please select a location"
        @locations = @production.organization.locations.order(:name)
        render :sessions, status: :unprocessable_entity and return
      end

      @wizard_state[:audition_sessions] ||= []
      existing_start_times = @wizard_state[:audition_sessions].map { |s| s[:start_at].to_s }.to_set
      current_time = Time.zone.parse(start_at)

      added = 0
      skipped = 0
      count.times do |_i|
        iso = current_time.iso8601
        if existing_start_times.include?(iso)
          skipped += 1
        else
          @wizard_state[:audition_sessions] << {
            start_at: iso,
            duration_minutes: duration,
            location_id: location_id,
            is_online: is_online,
            online_location_info: online_location_info
          }
          existing_start_times << iso
          added += 1
        end
        current_time += duration.minutes
      end

      save_wizard_state

      notice =
        if added.zero?
          "No new sessions generated — all #{count} would have duplicated existing sessions."
        elsif skipped.zero?
          "#{added} sessions generated"
        else
          "#{added} sessions generated (#{skipped} skipped — already on the schedule)"
        end
      redirect_to manage_signups_auditions_wizard_sessions_path(@production), notice: notice
    end

    def add_session
      start_at = params[:start_at]
      duration = params[:duration_minutes].to_i
      is_online = ActiveModel::Type::Boolean.new.cast(params[:is_online])
      location_id = is_online ? nil : params[:location_id]
      online_location_info = is_online ? params[:online_location_info].presence : nil

      if start_at.blank? || duration <= 0 || (!is_online && location_id.blank?)
        flash[:alert] = "Please fill in all session details"
        redirect_to manage_signups_auditions_wizard_sessions_path(@production) and return
      end

      @wizard_state[:audition_sessions] ||= []
      @wizard_state[:audition_sessions] << {
        start_at: Time.zone.parse(start_at).iso8601,
        duration_minutes: duration,
        location_id: location_id,
        is_online: is_online,
        online_location_info: online_location_info
      }

      save_wizard_state
      redirect_to manage_signups_auditions_wizard_sessions_path(@production), notice: "Session added"
    end

    def update_session
      index = params[:session_index].to_i
      session_data = @wizard_state[:audition_sessions][index]

      if session_data
        session_data[:start_at] = Time.zone.parse(params[:start_at]).iso8601 if params[:start_at].present?
        session_data[:duration_minutes] = params[:duration_minutes].to_i if params[:duration_minutes].present?
        if params.key?(:is_online)
          is_online = ActiveModel::Type::Boolean.new.cast(params[:is_online])
          session_data[:is_online] = is_online
          if is_online
            session_data[:location_id] = nil
            session_data[:online_location_info] = params[:online_location_info].presence
          else
            session_data[:location_id] = params[:location_id] if params[:location_id].present?
            session_data[:online_location_info] = nil
          end
        elsif params[:location_id].present?
          session_data[:location_id] = params[:location_id]
        end
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

    def delete_all_sessions
      @wizard_state[:audition_sessions] = []
      save_wizard_state
      redirect_to manage_signups_auditions_wizard_sessions_path(@production), notice: "All sessions removed"
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
      redirect_to manage_signups_auditions_wizard_form_starter_path(@production)
    end

    # Step 6: Form Starter (build the form's questions)
    def form_starter
      @wizard_state[:form_starter_questions] ||= []
    end

    def save_form_starter
      if params.key?(:resume_required)
        @wizard_state[:resume_required] = params[:resume_required] == "1"
      end
      save_wizard_state
      redirect_to manage_signups_auditions_wizard_review_path(@production)
    end

    def add_form_question
      text = params[:text].to_s.strip
      if text.blank?
        flash[:alert] = "Question text is required"
        redirect_to manage_signups_auditions_wizard_form_starter_path(@production) and return
      end

      type_class = QuestionTypes::Base.find(params[:question_type])
      qtype = type_class ? type_class.key : "textarea"

      options = if type_class&.needs_options?
        params[:options].to_s.split("\n").map(&:strip).reject(&:blank?)
      else
        []
      end

      if type_class&.needs_options? && options.empty?
        flash[:alert] = "This question type needs at least one option"
        redirect_to manage_signups_auditions_wizard_form_starter_path(@production) and return
      end

      @wizard_state[:form_starter_questions] ||= []
      @wizard_state[:form_starter_questions] << {
        text: text,
        question_type: qtype,
        required: params[:required] == "1",
        options: options
      }
      save_wizard_state
      redirect_to manage_signups_auditions_wizard_form_starter_path(@production), notice: "Question added"
    end

    def delete_form_question
      @wizard_state[:form_starter_questions]&.delete_at(params[:index].to_i)
      save_wizard_state
      redirect_to manage_signups_auditions_wizard_form_starter_path(@production), notice: "Question removed"
    end

    def update_form_question
      index = params[:index].to_i
      questions = @wizard_state[:form_starter_questions] || []
      if questions[index].nil?
        flash[:alert] = "Question not found"
        redirect_to manage_signups_auditions_wizard_form_starter_path(@production) and return
      end

      text = params[:text].to_s.strip
      if text.blank?
        flash[:alert] = "Question text is required"
        redirect_to manage_signups_auditions_wizard_form_starter_path(@production) and return
      end

      type_class = QuestionTypes::Base.find(params[:question_type])
      qtype = type_class ? type_class.key : "textarea"

      options = if type_class&.needs_options?
        params[:options].to_s.split("\n").map(&:strip).reject(&:blank?)
      else
        []
      end

      if type_class&.needs_options? && options.empty?
        flash[:alert] = "This question type needs at least one option"
        redirect_to manage_signups_auditions_wizard_form_starter_path(@production) and return
      end

      questions[index] = {
        text: text,
        question_type: qtype,
        required: params[:required] == "1",
        options: options
      }
      @wizard_state[:form_starter_questions] = questions
      save_wizard_state
      redirect_to manage_signups_auditions_wizard_form_starter_path(@production), notice: "Question updated"
    end

    # Step 7: Review & Create
    def review
      # Show summary of all settings before creating
    end

    def create_cycle
      @audition_cycle = AuditionCycle.new(
        production: @production,
        active: true,
        # The wizard's form_starter step IS the form review — anyone who finished
        # the wizard has explicitly designed the questions. Default to ready
        # rather than making them click an extra "Mark Ready" button afterwards.
        form_reviewed: true,
        allow_video_submissions: @wizard_state[:allow_video_submissions],
        allow_in_person_auditions: @wizard_state[:allow_in_person_auditions],
        listed_in_directory: @wizard_state[:listed_in_directory] != false,
        # Default true preserves existing behavior — the producer can opt
        # out via the toggle on the format step.
        resume_required: @wizard_state[:resume_required] != false,
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
                start_at: Time.zone.parse(session_data[:start_at]),
                location_id: session_data[:location_id]
              )
            end
          end

          # Seed starter form questions.
          # Build options on the question BEFORE saving so the
          # validate_question_options_presence check passes for
          # multiple-single / multiple-multiple / ranking types.
          starter_questions = @wizard_state[:form_starter_questions] || []
          starter_questions.each_with_index do |q, idx|
            question = @audition_cycle.questions.new(
              text: q[:text] || q["text"],
              question_type: q[:question_type] || q["question_type"],
              required: q[:required] || q["required"] || false,
              position: idx
            )
            (q[:options] || q["options"] || []).each do |opt_text|
              question.question_options.build(text: opt_text)
            end
            question.save!
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
    rescue ActiveRecord::RecordInvalid => e
      # Catches failures from any of the create!/save! calls above (sessions,
      # reviewers, questions). Without this rescue the exception escapes the
      # action and the user sees a 500 with no idea what to fix.
      flash.now[:alert] = "Couldn't create the audition cycle: #{e.record.errors.full_messages.to_sentence.presence || e.message}"
      render :review, status: :unprocessable_entity
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
      @wizard_state_record = AuditionWizardState.find_or_create_by!(
        production: @production,
        user: Current.user
      )

      # One-time migration: if there's leftover state in the legacy session cookie
      # and the DB row is still empty, copy it over and clear the cookie. Lets
      # mid-wizard users keep their progress through the storage change.
      if @wizard_state_record.state.blank? &&
         session[:audition_wizard].is_a?(Hash) &&
         session[:audition_wizard][@production.id.to_s].present?
        @wizard_state_record.update!(state: session[:audition_wizard][@production.id.to_s])
      end
      session[:audition_wizard]&.delete(@production.id.to_s)

      @wizard_state = @wizard_state_record.state.with_indifferent_access

      # Surface wizard state on any Sentry event fired during this request so
      # we can debug what the user had configured when something blows up.
      sentry_context("audition_wizard", {
        wizard_state_id: @wizard_state_record.id,
        production_id: @production.id,
        updated_at: @wizard_state_record.updated_at&.iso8601,
        keys: @wizard_state.keys.sort,
        starter_question_count: (@wizard_state[:form_starter_questions] || []).size,
        audition_session_count: (@wizard_state[:audition_sessions] || []).size,
        starter_questions: (@wizard_state[:form_starter_questions] || []).map { |q|
          {
            type: q[:question_type] || q["question_type"],
            required: q[:required] || q["required"],
            options_count: (q[:options] || q["options"] || []).size
          }
        }
      })
    end

    def save_wizard_state
      @wizard_state_record.update!(state: @wizard_state.to_h)
    end

    def clear_wizard_state
      AuditionWizardState.where(production: @production, user: Current.user).delete_all
    end
  end
end

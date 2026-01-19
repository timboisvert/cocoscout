# frozen_string_literal: true

module Manage
  class AuditionCyclesController < Manage::ManageController
    before_action :set_production
    before_action :check_production_access
    before_action :set_audition_cycle,
                  only: %i[show edit form update destroy preview create_question update_question destroy_question reorder_questions
                           archive delete_confirm toggle_voting]
    before_action :set_question, only: %i[update_question destroy_question]
    before_action :ensure_user_is_manager, except: %i[preview show]

    def new
      @audition_cycle = AuditionCycle.new
      # Set default closes_at to 2 weeks from now
      @audition_cycle.closes_at = 2.weeks.from_now.change(hour: 23, min: 59)
    end

    def show
      # Summary view for archived auditions
      @custom_questions = @audition_cycle.questions.order(:position)
      @audition_requests = @audition_cycle.audition_requests.includes(:requestable).order(created_at: :desc)

      # For in-person auditions, get person requests (not group requests)
      @accepted_requests = @audition_requests.where(requestable_type: "Person")

      # Get people added to casts during this audition cycle via cast_assignment_stages
      person_ids = CastAssignmentStage.where(audition_cycle_id: @audition_cycle.id, assignable_type: "Person")
                                      .pluck(:assignable_id)
                                      .uniq
      @cast_people = Person.where(id: person_ids).order(:name)
    end

    def create
      @audition_cycle = AuditionCycle.new(audition_cycle_params)
      @audition_cycle.production = @production
      @audition_cycle.active = true

      # Generate unique token using ShortKeyService
      @audition_cycle.token = ShortKeyService.generate(type: :audition)

      ActiveRecord::Base.transaction do
        # Deactivate all other audition cycles for this production
        @production.audition_cycles.where(active: true).update_all(active: false)

        raise ActiveRecord::Rollback unless @audition_cycle.save

        redirect_to manage_production_signups_auditions_path(@production), notice: "Audition Cycle was successfully scheduled"
      end

      render :new, status: :unprocessable_entity unless @audition_cycle.persisted?
    end

    def edit; end

    def form
      # Load existing question if question_id is present, otherwise create a new one
      if params[:question_id].present?
        @question = @audition_cycle.questions.find(params[:question_id])
      else
        @question = @audition_cycle.questions.new
        type_class = @question.question_type_class
        @question.question_options.build if type_class&.needs_options?
      end
      @questions = @audition_cycle.questions.order(:position)
      @shows = @production.shows.where("date_and_time >= ?", Time.current).order(:date_and_time)
    end

    def update
      params_to_update = audition_cycle_params

      # Convert form_reviewed to proper boolean
      if params_to_update[:form_reviewed].present?
        params_to_update[:form_reviewed] = params_to_update[:form_reviewed] == "1"
      end

      if params_to_update[:availability_show_ids].present?
        params_to_update[:availability_show_ids] = params_to_update[:availability_show_ids].reject(&:blank?).map(&:to_i)
        params_to_update[:availability_show_ids] = nil if params_to_update[:availability_show_ids].empty?
      end

      if @audition_cycle.update(params_to_update)
        # Redirect based on source
        if params[:redirect_to] == "form"
          redirect_to form_manage_production_signups_auditions_cycle_path(@production, @audition_cycle, tab: params[:tab]),
                      notice: "Form saved",
                      status: :see_other
        else
          redirect_to prepare_manage_production_signups_auditions_cycle_path(@production, @audition_cycle),
                      notice: "Audition Settings successfully updated",
                      status: :see_other
        end
      else
        # On error, render the appropriate view
        if params[:redirect_to] == "form"
          setup_form_variables
          render :form, status: :unprocessable_entity
        else
          render :edit, status: :unprocessable_entity
        end
      end
    end

    # DELETE /audition_cycles/1
    def delete_confirm
      # Confirmation page before deleting
      return unless @audition_cycle.active

      redirect_to manage_production_signups_auditions_cycle_path(@production, @audition_cycle),
                  alert: "Only archived audition cycles can be deleted"
    end

    def destroy
      if @audition_cycle.active
        redirect_to manage_production_signups_auditions_cycle_path(@production, @audition_cycle),
                    alert: "Only archived audition cycles can be deleted"
        return
      end

      @audition_cycle.destroy!
      redirect_to manage_production_signups_auditions_path(@production), notice: "Audition Cycle was successfully deleted",
                                                                 status: :see_other
    end

    def preview
      @audition_request = AuditionRequest.new
      @person = Person.new
      @questions = @audition_cycle.questions.order(:position)
      @answers = {}

      # Load shows for availability section if enabled
      if @audition_cycle.include_availability_section
        @shows = @production.shows.where("date_and_time >= ?", Time.current).order(:date_and_time)

        # Filter shows by selected show ids if specified
        @shows = @shows.where(id: @audition_cycle.availability_show_ids) if @audition_cycle.availability_show_ids.present?

        # Initialize empty availability data for preview
        @availability = {}
      end

      # Load audition sessions for audition availability section if enabled
      if @audition_cycle.include_audition_availability_section
        # For preview, show all sessions (not just future ones) so managers can see what was set up
        @audition_sessions = @audition_cycle.audition_sessions.order(:start_at)

        # Initialize empty audition availability data for preview
        @audition_availability = {}
      end
    end

    # POST /audition_cycles/:id/create_question
    def create_question
      @question = Question.new(question_params)
      @question.questionable = @audition_cycle
      # Set position to the end of the list
      max_position = @audition_cycle.questions.maximum(:position)
      @question.position = max_position ? max_position + 1 : 1
      @questions = @audition_cycle.questions.order(:position)

      if @question.save
        redirect_to form_manage_production_signups_auditions_cycle_path(@production, @audition_cycle, questions_open: true),
                    notice: "Question was successfully created"
      else
        @question_error = true
        render :form, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /audition_cycles/:id/update_question/:question_id
    def update_question
      if @question.update(question_params)
        redirect_to form_manage_production_signups_auditions_cycle_path(@production, @audition_cycle, questions_open: true),
                    notice: "Question was successfully updated", status: :see_other
      else
        render :form, status: :unprocessable_entity
      end
    end

    # DELETE /audition_cycles/:id/destroy_question/:question_id
    def destroy_question
      @question.destroy!
      redirect_to form_manage_production_signups_auditions_cycle_path(@production, @audition_cycle, questions_open: true),
                  notice: "Question was successfully deleted", status: :see_other
    end

    # POST /audition_cycles/:id/reorder_questions
    def reorder_questions
      ids = params[:ids]
      questions = @audition_cycle.questions.where(id: ids)
      ActiveRecord::Base.transaction do
        ids.each_with_index do |id, idx|
          questions.find { |q| q.id == id.to_i }&.update(position: idx + 1)
        end
      end
      head :ok
    end

    # PATCH /audition_cycles/:id/archive
    def archive
      if @audition_cycle.update(active: false)
        redirect_to manage_production_signups_auditions_path(@production), notice: "Audition Cycle has been archived",
                                                                   status: :see_other
      else
        redirect_to manage_production_signups_auditions_path(@production), alert: "Failed to archive Audition Cycle",
                                                                   status: :see_other
      end
    end

    # PATCH /audition_cycles/:id/toggle_voting
    def toggle_voting
      voting_type = params[:voting_type] || "request"
      voting_enabled = params[:voting_enabled]

      if voting_type == "audition"
        if @audition_cycle.update(audition_voting_enabled: voting_enabled)
          render json: { success: true, voting_enabled: @audition_cycle.audition_voting_enabled }
        else
          render json: { success: false, error: "Failed to update voting status" }, status: :unprocessable_entity
        end
      else
        if @audition_cycle.update(voting_enabled: voting_enabled)
          render json: { success: true, voting_enabled: @audition_cycle.voting_enabled }
        else
          render json: { success: false, error: "Failed to update voting status" }, status: :unprocessable_entity
        end
      end
    end

    private

    def setup_form_variables
      if params[:question_id].present?
        @question = @audition_cycle.questions.find(params[:question_id])
      else
        @question = @audition_cycle.questions.new
        type_class = @question.question_type_class
        @question.question_options.build if type_class&.needs_options?
      end
      @questions = @audition_cycle.questions.order(:position)
    end

    def set_production
      unless Current.organization
        redirect_to select_organization_path, alert: "Please select an organization first."
        return
      end
      @production = Current.organization.productions.find(params.expect(:production_id))
      sync_current_production(@production)
    end

    def set_audition_cycle
      @audition_cycle = AuditionCycle.find(params.expect(:id))
    end

    def set_question
      @question = @audition_cycle.questions.find(params[:question_id]) if params[:question_id]
    end

    def audition_cycle_params
      params.require(:audition_cycle).permit(:production_id, :opens_at, :closes_at, :audition_type,
                                             :allow_video_submissions, :allow_in_person_auditions,
                                             :instruction_text, :notify_on_submission,
                                             :video_field_text, :success_text, :token, :include_availability_section, :require_all_availability, :include_audition_availability_section, :require_all_audition_availability, :form_reviewed, availability_show_ids: [])
    end

    def question_params
      params.require(:question).permit(:key, :text, :question_type, :required, :questionable_id, :questionable_type,
                                       question_options_attributes: %i[id text _destroy])
    end
  end
end

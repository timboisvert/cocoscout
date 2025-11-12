class Manage::AuditionCyclesController < Manage::ManageController
  before_action :set_production
  before_action :check_production_access
  before_action :set_audition_cycle, only: %i[ show edit form update destroy preview create_question update_question destroy_question reorder_questions archive ]
  before_action :set_question, only: %i[ update_question destroy_question ]
  before_action :ensure_user_is_manager, except: %i[ preview show ]

  # Skip the sidebar on the preview
  skip_before_action :show_manage_sidebar, only: %i[ preview ]

  # Use the public facing layout on the preview
  layout "application"

  def new
    @audition_cycle = AuditionCycle.new
  end

  def show
    # Summary view for archived auditions
    @custom_questions = @audition_cycle.questions.order(:position)
    @audition_requests = @audition_cycle.audition_requests.includes(:person).order(created_at: :desc)
    @accepted_requests = @audition_requests.where(status: :accepted)

    # Get people added to casts during this audition cycle via cast_assignment_stages
    @cast_people = Person.joins(:cast_assignment_stages)
                         .where(cast_assignment_stages: { audition_cycle_id: @audition_cycle.id })
                         .distinct
                         .order(:name)
  end

  def create
    @audition_cycle = AuditionCycle.new(audition_cycle_params)
    @audition_cycle.production = @production
    @audition_cycle.active = true

    # Create a random hex code for the audition link
    @audition_cycle.token = SecureRandom.alphanumeric(5).upcase

    # Make sure it's unique and regenerate if not
    while AuditionCycle.exists?(token: @audition_cycle.token)
      @audition_cycle.token = SecureRandom.alphanumeric(5).upcase
    end

    ActiveRecord::Base.transaction do
      # Deactivate all other audition cycles for this production
      @production.audition_cycles.where(active: true).update_all(active: false)

      if @audition_cycle.save
        redirect_to manage_production_auditions_path(@production), notice: "Audition Cycle was successfully scheduled"
      else
        raise ActiveRecord::Rollback
      end
    end

    render :new, status: :unprocessable_entity unless @audition_cycle.persisted?
  end

  def edit
  end

  def form
    # Load existing question if question_id is present, otherwise create a new one
    if params[:question_id].present?
      @question = @audition_cycle.questions.find(params[:question_id])
    else
      @question = @audition_cycle.questions.new
      @question.question_options.build if [ "multiple-multiple", "multiple-single" ].include?(@question.question_type)
    end
    @questions = @audition_cycle.questions.order(:position)
  end

  def update
    params_to_update = audition_cycle_params

    # Convert form_reviewed to proper boolean
    if params_to_update[:form_reviewed].present?
      params_to_update[:form_reviewed] = params_to_update[:form_reviewed] == "1"
    end

    if params_to_update[:availability_event_types].present?
      params_to_update[:availability_event_types] = params_to_update[:availability_event_types].reject(&:blank?)
      params_to_update[:availability_event_types] = nil if params_to_update[:availability_event_types].empty?
    end

    if @audition_cycle.update(params_to_update)
      # Check if this is from the form page (availability, text sections, or form_reviewed)
      if params[:audition_cycle]&.key?(:include_availability_section) ||
         params[:audition_cycle]&.key?(:availability_event_types) ||
         params[:audition_cycle]&.key?(:header_text) ||
         params[:audition_cycle]&.key?(:video_field_text) ||
         params[:audition_cycle]&.key?(:success_text) ||
         params[:audition_cycle]&.keys == [ "form_reviewed" ]

        # Determine the appropriate notice message
        if params[:audition_cycle]&.key?(:include_availability_section) || params[:audition_cycle]&.key?(:availability_event_types)
          notice_message = "Availability settings successfully updated"
        elsif params[:audition_cycle]&.key?(:header_text) || params[:audition_cycle]&.key?(:video_field_text) || params[:audition_cycle]&.key?(:success_text)
          notice_message = "Text successfully updated"
        else
          notice_message = "Form review status successfully updated"
        end

        redirect_to form_manage_production_audition_cycle_path(@production, @audition_cycle),
                    notice: notice_message,
                    status: :see_other
      else
        redirect_to prepare_manage_production_audition_cycle_path(@production, @audition_cycle),
                    notice: "Audition Settings successfully updated",
                    status: :see_other
      end
    else
      # Determine which view to render based on what params were sent
      # If form_reviewed is the only param, it came from the form page
      # Otherwise it came from the edit page
      if params[:audition_cycle]&.keys == [ "form_reviewed" ]
        setup_form_variables
        render :form, status: :unprocessable_entity
      else
        render :edit, status: :unprocessable_entity
      end
    end
  end

  # DELETE /audition_cycles/1
  def destroy
    @audition_cycle.destroy!
    redirect_to [ :manage, @production ], notice: "Audition Cycle was successfully deleted", status: :see_other
  end

  def preview
    @audition_request = AuditionRequest.new
    @person = @audition_request.build_person
    @questions = @audition_cycle.questions.order(:position)
    @answers = {}

    # Load shows for availability section if enabled
    if @audition_cycle.include_availability_section
      @shows = @production.shows.order(:date_and_time)

      # Filter shows by selected event types if specified
      if @audition_cycle.availability_event_types.present?
        @shows = @shows.where(event_type: @audition_cycle.availability_event_types)
      end

      # Initialize empty availability data for preview
      @availability = {}
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
      redirect_to form_manage_production_audition_cycle_path(@production, @audition_cycle, questions_open: true), notice: "Question was successfully created"
    else
      @question_error = true
      render :form, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /audition_cycles/:id/update_question/:question_id
  def update_question
    if @question.update(question_params)
      redirect_to form_manage_production_audition_cycle_path(@production, @audition_cycle, questions_open: true), notice: "Question was successfully updated", status: :see_other
    else
      render :form, status: :unprocessable_entity
    end
  end

  # DELETE /audition_cycles/:id/destroy_question/:question_id
  def destroy_question
    @question.destroy!
    redirect_to form_manage_production_audition_cycle_path(@production, @audition_cycle, questions_open: true), notice: "Question was successfully deleted", status: :see_other
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
      redirect_to manage_production_auditions_path(@production), notice: "Audition Cycle has been archived", status: :see_other
    else
      redirect_to manage_production_auditions_path(@production), alert: "Failed to archive Audition Cycle", status: :see_other
    end
  end

  private

  def setup_form_variables
    if params[:question_id].present?
      @question = @audition_cycle.questions.find(params[:question_id])
    else
      @question = @audition_cycle.questions.new
      @question.question_options.build if [ "multiple-multiple", "multiple-single" ].include?(@question.question_type)
    end
    @questions = @audition_cycle.questions.order(:position)
  end

  def set_production
    @production = Current.organization.productions.find(params.expect(:production_id))
  end

  def set_audition_cycle
    @audition_cycle = AuditionCycle.find(params.expect(:id))
  end

  def set_question
    @question = @audition_cycle.questions.find(params[:question_id]) if params[:question_id]
  end

  def audition_cycle_params
    params.require(:audition_cycle).permit(:production_id, :opens_at, :closes_at, :audition_type, :header_text, :video_field_text, :success_text, :token, :include_availability_section, :require_all_availability, :form_reviewed, availability_event_types: [])
  end

  def question_params
    params.require(:question).permit(:key, :text, :question_type, :required, :questionable_id, :questionable_type, question_options_attributes: [ :id, :text, :_destroy ])
  end
end

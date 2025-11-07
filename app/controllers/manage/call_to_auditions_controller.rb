class Manage::CallToAuditionsController < Manage::ManageController
  before_action :set_production
  before_action :check_production_access
  before_action :set_call_to_audition, only: %i[ edit form update destroy preview create_question update_question destroy_question reorder_questions ]
  before_action :set_question, only: %i[ update_question destroy_question ]
  before_action :ensure_user_is_manager, except: %i[ preview ]

  # Skip the sidebar on the preview
  skip_before_action :show_manage_sidebar, only: %i[ preview ]

  # Use the public facing layout on the preview
  layout "application"

  def new
    @call_to_audition = CallToAudition.new
  end

  def create
    @call_to_audition = CallToAudition.new(call_to_audition_params)
    @call_to_audition.production = @production

    # Create a random hex code for the audition link
    @call_to_audition.token = SecureRandom.alphanumeric(5).upcase

    # Make sure it's unique and regenerate if not
    while CallToAudition.exists?(token: @call_to_audition.token)
      @call_to_audition.token = SecureRandom.alphanumeric(5).upcase
    end

    if @call_to_audition.save
      redirect_to manage_production_auditions_path(@production), notice: "Call to Audition was successfully scheduled"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def form
    # Load existing question if question_id is present, otherwise create a new one
    if params[:question_id].present?
      @question = @call_to_audition.questions.find(params[:question_id])
    else
      @question = @call_to_audition.questions.new
      @question.question_options.build if [ "multiple-multiple", "multiple-single" ].include?(@question.question_type)
    end
    @questions = @call_to_audition.questions.order(:position)
  end

  def update
    # Clean up availability_event_types to remove empty strings
    params_to_update = call_to_audition_params
    if params_to_update[:availability_event_types].present?
      params_to_update[:availability_event_types] = params_to_update[:availability_event_types].reject(&:blank?)
      params_to_update[:availability_event_types] = nil if params_to_update[:availability_event_types].empty?
    end

    if @call_to_audition.update(params_to_update)
      redirect_to manage_production_auditions_prepare_path(@production),
                  notice: "Audition Settings successfully updated",
                  status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /call_to_auditions/1
  def destroy
    @call_to_audition.destroy!
    redirect_to [ :manage, @production ], notice: "Call to Audition was successfully deleted", status: :see_other
  end

  def preview
    @audition_request = AuditionRequest.new
    @person = @audition_request.build_person
    @questions = @call_to_audition.questions.order(:position)
    @answers = {}

    # Load shows for availability section if enabled
    if @call_to_audition.include_availability_section
      @shows = @production.shows.order(:date_and_time)

      # Filter shows by selected event types if specified
      if @call_to_audition.availability_event_types.present?
        @shows = @shows.where(event_type: @call_to_audition.availability_event_types)
      end

      # Initialize empty availability data for preview
      @availability = {}
    end
  end

  # POST /call_to_auditions/:id/create_question
  def create_question
    @question = Question.new(question_params)
    @question.questionable = @call_to_audition
    # Set position to the end of the list
    max_position = @call_to_audition.questions.maximum(:position)
    @question.position = max_position ? max_position + 1 : 1
    @questions = @call_to_audition.questions.order(:position)

    if @question.save
      redirect_to form_manage_production_call_to_audition_path(@production, @call_to_audition, questions_open: true), notice: "Question was successfully created"
    else
      @question_error = true
      render :form, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /call_to_auditions/:id/update_question/:question_id
  def update_question
    if @question.update(question_params)
      redirect_to form_manage_production_call_to_audition_path(@production, @call_to_audition, questions_open: true), notice: "Question was successfully updated", status: :see_other
    else
      render :form, status: :unprocessable_entity
    end
  end

  # DELETE /call_to_auditions/:id/destroy_question/:question_id
  def destroy_question
    @question.destroy!
    redirect_to form_manage_production_call_to_audition_path(@production, @call_to_audition, questions_open: true), notice: "Question was successfully deleted", status: :see_other
  end

  # POST /call_to_auditions/:id/reorder_questions
  def reorder_questions
    ids = params[:ids]
    questions = @call_to_audition.questions.where(id: ids)
    ActiveRecord::Base.transaction do
      ids.each_with_index do |id, idx|
        questions.find { |q| q.id == id.to_i }&.update(position: idx + 1)
      end
    end
    head :ok
  end

  private

  def set_production
    @production = Current.production_company.productions.find(params.expect(:production_id))
  end

  def set_call_to_audition
    @call_to_audition = CallToAudition.find(params.expect(:id))
  end

  def set_question
    @question = @call_to_audition.questions.find(params[:question_id]) if params[:question_id]
  end

    def call_to_audition_params
      params.expect(call_to_audition: [ :production_id, :opens_at, :closes_at, :audition_type, :header_text, :video_field_text, :success_text, :token, :include_availability_section, :require_all_availability, :form_reviewed, { availability_event_types: [] } ])
    end

  def question_params
    params.require(:question).permit(:key, :text, :question_type, :required, :questionable_id, :questionable_type, question_options_attributes: [ :id, :text, :_destroy ])
  end
end

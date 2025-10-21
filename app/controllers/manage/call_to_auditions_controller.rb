class Manage::CallToAuditionsController < Manage::ManageController
  before_action :set_production
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

    # Calculate the tab index for Custom Questions (it's the last tab)
    @questions_tab_index = @call_to_audition.audition_type == "video_upload" ? 3 : 2
  end

  def update
    if @call_to_audition.update(call_to_audition_params)
      # Preserve the active tab by including it in the redirect
      tab_param = params[:active_tab].present? ? { tab: params[:active_tab] } : {}

      redirect_to form_manage_production_call_to_audition_path(@production, @call_to_audition, tab_param),
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
      # Calculate the tab index for Custom Questions (it's the last tab)
      questions_tab_index = @call_to_audition.audition_type == "video_upload" ? 3 : 2
      redirect_to form_manage_production_call_to_audition_path(@production, @call_to_audition, tab: questions_tab_index), notice: "Question was successfully created"
    else
      @question_error = true
      render :form, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /call_to_auditions/:id/update_question/:question_id
  def update_question
    if @question.update(question_params)
      # Calculate the tab index for Custom Questions (it's the last tab)
      questions_tab_index = @call_to_audition.audition_type == "video_upload" ? 3 : 2
      redirect_to form_manage_production_call_to_audition_path(@production, @call_to_audition, tab: questions_tab_index), notice: "Question was successfully updated", status: :see_other
    else
      render :form, status: :unprocessable_entity
    end
  end

  # DELETE /call_to_auditions/:id/destroy_question/:question_id
  def destroy_question
    @question.destroy!
    # Calculate the tab index for Custom Questions (it's the last tab)
    questions_tab_index = @call_to_audition.audition_type == "video_upload" ? 3 : 2
    redirect_to form_manage_production_call_to_audition_path(@production, @call_to_audition, tab: questions_tab_index), notice: "Question was successfully deleted", status: :see_other
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
      params.expect(call_to_audition: [ :production_id, :opens_at, :closes_at, :audition_type, :header_text, :video_field_text, :success_text, :token ])
    end

  def question_params
    params.require(:question).permit(:key, :text, :question_type, :required, :questionable_id, :questionable_type, question_options_attributes: [ :id, :text, :_destroy ])
  end
end

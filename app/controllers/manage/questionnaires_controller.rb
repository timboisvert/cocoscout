class Manage::QuestionnairesController < Manage::ManageController
  before_action :set_production
  before_action :set_questionnaire, only: [ :show, :edit, :update, :archive, :form, :preview, :create_question, :update_question, :destroy_question, :reorder_questions, :responses, :show_response, :invite_people ]

  def index
    @filter = params[:filter] || "all"

    case @filter
    when "accepting"
      @questionnaires = @production.questionnaires.where(archived_at: nil, accepting_responses: true).order(created_at: :desc)
    when "archived"
      @questionnaires = @production.questionnaires.where.not(archived_at: nil).order(archived_at: :desc)
    else # 'all'
      @questionnaires = @production.questionnaires.where(archived_at: nil).order(created_at: :desc)
    end
  end

  def show
    @questions = @questionnaire.questions.order(:position)
  end

  def new
    @questionnaire = @production.questionnaires.new
  end

  def create
    @questionnaire = @production.questionnaires.new(questionnaire_params)

    if @questionnaire.save
      redirect_to form_manage_production_questionnaire_path(@production, @questionnaire), notice: "Questionnaire created successfully"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @questionnaire.update(questionnaire_params)
      respond_to do |format|
        format.html { redirect_to manage_production_questionnaire_path(@production, @questionnaire), notice: "Questionnaire updated successfully" }
        format.json { render json: { success: true, accepting_responses: @questionnaire.accepting_responses } }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { success: false, errors: @questionnaire.errors }, status: :unprocessable_entity }
      end
    end
  end

  def archive
    @questionnaire.update(archived_at: Time.current)
    redirect_to manage_production_questionnaires_path(@production), notice: "Questionnaire archived successfully"
  end

  def form
    @questions = @questionnaire.questions.order(:position)

    # Check if we're editing a specific question
    if params[:question_id].present?
      @question = @questionnaire.questions.find(params[:question_id])
    else
      @question = @questionnaire.questions.new
    end
  end

  def preview
    @questions = @questionnaire.questions.order(:position)
  end

  def create_question
    @question = @questionnaire.questions.new(question_params)

    # Set position as the last question
    max_position = @questionnaire.questions.maximum(:position) || 0
    @question.position = max_position + 1

    if @question.save
      redirect_to form_manage_production_questionnaire_path(@production, @questionnaire), notice: "Question added successfully"
    else
      @questions = @questionnaire.questions.order(:position)
      render :form, status: :unprocessable_entity
    end
  end

  def update_question
    @question = @questionnaire.questions.find(params[:question_id])

    if @question.update(question_params)
      redirect_to form_manage_production_questionnaire_path(@production, @questionnaire), notice: "Question updated successfully"
    else
      @questions = @questionnaire.questions.order(:position)
      render :form, status: :unprocessable_entity
    end
  end

  def destroy_question
    @question = @questionnaire.questions.find(params[:question_id])
    @question.destroy
    redirect_to form_manage_production_questionnaire_path(@production, @questionnaire), notice: "Question deleted successfully"
  end

  def reorder_questions
    params[:question_ids].each_with_index do |id, index|
      @questionnaire.questions.find(id).update(position: index + 1)
    end

    head :ok
  end

  def responses
    @responses = @questionnaire.questionnaire_responses
                               .includes(:person)
                               .order(created_at: :desc)
  end

  def show_response
    @response = @questionnaire.questionnaire_responses.find(params[:response_id])
    @questions = @questionnaire.questions.order(:position)
    @answers = {}
    @questions.each do |question|
      answer = @response.questionnaire_answers.find_by(question: question)
      @answers["#{question.id}"] = answer.value if answer
    end
  end

  def invite_people
    recipient_type = params[:recipient_type]
    cast_id = params[:cast_id]
    person_ids = params[:person_ids] || []
    message_template = params[:message]

    # Get all people in the production
    all_people = @production.casts.flat_map(&:people).uniq

    # Determine recipients based on recipient_type
    recipients = if recipient_type == "all"
      all_people
    elsif recipient_type == "cast"
      Cast.find(cast_id).people
    elsif recipient_type == "specific"
      Person.where(id: person_ids)
    else
      []
    end

    # Create invitations
    recipients.each do |person|
      QuestionnaireInvitation.find_or_create_by(
        questionnaire: @questionnaire,
        person_id: person.id
      )

      # Send email if person has a user account
      if person.user
        Manage::QuestionnaireMailer.invitation(person, @questionnaire, @production, message_template).deliver_later
      end
    end

    redirect_to manage_production_questionnaire_path(@production, @questionnaire), notice: "Invited #{recipients.count} #{'person'.pluralize(recipients.count)}"
  end

  private

  def set_production
    @production = Current.organization.productions.find(params[:production_id])
  end

  def set_questionnaire
    @questionnaire = @production.questionnaires.find(params[:id])
  end

  def questionnaire_params
    params.require(:questionnaire).permit(:title, :instruction_text, :accepting_responses)
  end

  def question_params
    params.require(:question).permit(:text, :question_type, :required, question_options_attributes: [ :id, :text, :_destroy ])
  end
end

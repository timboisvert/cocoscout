class Manage::QuestionnairesController < ApplicationController
  before_action :set_production
  before_action :set_questionnaire, only: [:show, :edit, :update, :destroy, :form, :preview, :create_question, :update_question, :destroy_question, :reorder_questions, :responses, :response]

  def index
    @questionnaires = @production.questionnaires.order(created_at: :desc)
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
      redirect_to manage_production_questionnaire_path(@production, @questionnaire), notice: "Questionnaire created successfully"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @questionnaire.update(questionnaire_params)
      redirect_to manage_production_questionnaire_path(@production, @questionnaire), notice: "Questionnaire updated successfully"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @questionnaire.destroy
    redirect_to manage_production_questionnaires_path(@production), notice: "Questionnaire deleted successfully"
  end

  def form
    @questions = @questionnaire.questions.order(:position)
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

  def response
    @response = @questionnaire.questionnaire_responses.find(params[:response_id])
    @questions = @questionnaire.questions.order(:position)
    @answers = {}
    @questions.each do |question|
      answer = @response.questionnaire_answers.find_by(question: question)
      @answers["#{question.id}"] = answer.value if answer
    end
  end

  def invite_people
    person_ids = params[:person_ids] || []
    
    person_ids.each do |person_id|
      QuestionnaireInvitation.find_or_create_by(
        questionnaire: @questionnaire,
        person_id: person_id
      )
    end
    
    redirect_to manage_production_questionnaire_path(@production, @questionnaire), notice: "People invited successfully"
  end

  private

  def set_production
    @production = Current.user.productions.find(params[:production_id])
  end

  def set_questionnaire
    @questionnaire = @production.questionnaires.find(params[:id])
  end

  def questionnaire_params
    params.require(:questionnaire).permit(:title, :header_text, :success_text, :accepting_responses)
  end

  def question_params
    params.require(:question).permit(:text, :question_type, :required, question_options_attributes: [:id, :text, :_destroy])
  end
end

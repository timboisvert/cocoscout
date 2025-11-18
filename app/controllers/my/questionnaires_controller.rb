class My::QuestionnairesController < ApplicationController
  allow_unauthenticated_access only: [ :entry, :inactive ]

  skip_before_action :show_my_sidebar, only: [ :entry, :form, :submitform, :success, :inactive ]

  before_action :ensure_user_is_signed_in, only: [ :form, :submitform, :success ]
  before_action :set_questionnaire_and_questions, except: [ :index ]

  def index
    @questionnaires = Current.user.person.invited_questionnaires
                                   .includes(:production)
                                   .order(created_at: :desc)
  end

  def entry
    # Entry point for questionnaire - will redirect to form if user is signed in
    if authenticated?
      redirect_to my_questionnaire_form_path(token: @questionnaire.token), status: :see_other
      return
    end

    @user = User.new
    session[:return_to] = my_questionnaire_form_path(token: @questionnaire.token)
  end

  def form
    unless authenticated?
      redirect_to questionnaire_entry_path(token: @questionnaire.token), status: :see_other
      return
    end

    @person = Current.user.person

    # Check if person is invited
    unless @questionnaire.questionnaire_invitations.exists?(person: @person)
      redirect_to my_dashboard_path, alert: "You are not invited to this questionnaire"
      return
    end

    # Check if questionnaire is still accepting responses
    unless @questionnaire.accepting_responses
      redirect_to my_questionnaire_inactive_path(token: @questionnaire.token), status: :see_other
      return
    end

    # Check if they've already responded
    if @questionnaire.questionnaire_responses.exists?(person: @person)
      @questionnaire_response = @questionnaire.questionnaire_responses.find_by(person: @person)
      @answers = {}
      @questions.each do |question|
        answer = @questionnaire_response.questionnaire_answers.find_by(question: question)
        @answers["#{question.id}"] = answer.value if answer
      end
    else
      @questionnaire_response = QuestionnaireResponse.new
      @answers = {}
      @questions.each do |question|
        @answers["#{question.id}"] = ""
      end
    end
  end

  def submitform
    @person = Current.user.person

    # Check if person is invited
    unless @questionnaire.questionnaire_invitations.exists?(person: @person)
      redirect_to my_dashboard_path, alert: "You are not invited to this questionnaire"
      return
    end

    # Check if questionnaire is still accepting responses
    unless @questionnaire.accepting_responses
      redirect_to my_questionnaire_inactive_path(token: @questionnaire.token), status: :see_other
      return
    end

    # Associate the person with the organization if not already
    organization = @questionnaire.production.organization
    unless @person.organizations.include?(organization)
      @person.organizations << organization
    end

    # Check if updating existing response
    if @questionnaire.questionnaire_responses.exists?(person: @person)
      @questionnaire_response = @questionnaire.questionnaire_responses.find_by(person: @person)

      # Update the answers
      @answers = {}
      if params[:question]
        params[:question].each do |id, keyValue|
          answer = @questionnaire_response.questionnaire_answers.find_or_initialize_by(question: Question.find(id))
          answer.value = keyValue
          answer.save!
          @answers["#{id}"] = answer.value
        end
      end
    else
      # New response
      @questionnaire_response = QuestionnaireResponse.new(person: @person)
      @questionnaire_response.questionnaire = @questionnaire

      # Loop through the questions and store the answers
      @answers = {}
      if params[:question]
        params[:question].each do |question|
          answer = @questionnaire_response.questionnaire_answers.build
          answer.question = Question.find question.first
          answer.value = question.last
          @answers["#{answer.question.id}"] = answer.value
        end
      end
    end

    # Validate required questions
    @missing_required_questions = []
    @questions.select(&:required).each do |question|
      answer_value = @answers["#{question.id}"]
      if answer_value.blank? || (answer_value.is_a?(Hash) && answer_value.values.all?(&:blank?))
        @missing_required_questions << question
      end
    end

    # Validate and save
    if @missing_required_questions.any?
      render :form, status: :unprocessable_entity
    elsif @questionnaire_response.valid?
      @questionnaire_response.save!
      redirect_to my_questionnaire_success_path(token: @questionnaire.token), status: :see_other
    else
      render :form
    end
  end

  def success
  end

  def inactive
    if @questionnaire.accepting_responses && params[:force].blank?
      redirect_to questionnaire_entry_path(token: @questionnaire.token), status: :see_other
    end
  end

  private

  def set_questionnaire_and_questions
    @questionnaire = Questionnaire.find_by(token: params[:token].upcase)
    @questions = @questionnaire.questions.order(:position) if @questionnaire.present?

    if @questionnaire.nil?
      redirect_to root_path, alert: "Invalid questionnaire"
      return
    end

    @production = @questionnaire.production
  end

  def ensure_user_is_signed_in
    unless authenticated?
      redirect_to questionnaire_entry_path(token: params[:token]), status: :see_other
    end
  end
end

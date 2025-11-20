class Manage::QuestionnairesController < Manage::ManageController
  before_action :set_production
  before_action :set_questionnaire, only: [ :show, :update, :archive, :unarchive, :form, :preview, :create_question, :update_question, :destroy_question, :reorder_questions, :responses, :show_response, :invite_people ]

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

  def update
    params_to_update = questionnaire_params

    # Clean availability_show_ids array
    if params_to_update[:availability_show_ids].present?
      params_to_update[:availability_show_ids] = params_to_update[:availability_show_ids].reject(&:blank?).map(&:to_i)
      params_to_update[:availability_show_ids] = nil if params_to_update[:availability_show_ids].empty?
    end

    if @questionnaire.update(params_to_update)
      respond_to do |format|
        format.html do
          # If updating from the form page (availability settings or title), redirect back to form
          if params[:questionnaire]&.key?(:include_availability_section) ||
             params[:questionnaire]&.key?(:availability_show_ids) ||
             params[:questionnaire]&.key?(:title) ||
             params[:questionnaire]&.key?(:require_all_availability) ||
             params[:questionnaire]&.key?(:instruction_text)
            redirect_to form_manage_production_questionnaire_path(@production, @questionnaire), notice: "Questionnaire updated successfully"
          else
            redirect_to manage_production_questionnaire_path(@production, @questionnaire), notice: "Questionnaire updated successfully"
          end
        end
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

  def unarchive
    @questionnaire.update(archived_at: nil)
    redirect_to manage_production_questionnaire_path(@production, @questionnaire), notice: "Questionnaire unarchived successfully"
  end

  def form
    @questions = @questionnaire.questions.order(:position)
    @shows = @production.shows.where("date_and_time >= ?", Time.current).order(:date_and_time)

    # Check if we're editing a specific question
    if params[:question_id].present?
      @question = @questionnaire.questions.find(params[:question_id])
    else
      @question = @questionnaire.questions.new
    end
  end

  def preview
    @questions = @questionnaire.questions.order(:position)

    # Load shows for availability section if enabled
    if @questionnaire.include_availability_section
      @shows = @production.shows.where("date_and_time >= ?", Time.current).order(:date_and_time)

      # Filter shows by selected show IDs if specified
      if @questionnaire.availability_show_ids.present?
        @shows = @shows.where(id: @questionnaire.availability_show_ids)
      end
    end
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

    # Load availability data if enabled
    if @questionnaire.include_availability_section
      @shows = @production.shows.where("date_and_time >= ?", Time.current).order(:date_and_time)

      # Filter by show ids if specified
      if @questionnaire.availability_show_ids.present?
        @shows = @shows.where(id: @questionnaire.availability_show_ids)
      end

      # Load availability data for this person
      @availability = {}
      ShowAvailability.where(person: @response.person, show_id: @shows.pluck(:id)).each do |show_availability|
        @availability["#{show_availability.show_id}"] = show_availability.status.to_s
      end
    end

    render :response
  end

  def invite_people
    recipient_type = params[:recipient_type]
    cast_id = params[:cast_id]
    person_ids = params[:person_ids] || []
    message_template = params[:message]

    # Get all people in the production
    all_people = @production.talent_pools.flat_map(&:people).uniq

    # Determine recipients based on recipient_type
    recipients = if recipient_type == "all"
      all_people
    elsif recipient_type == "cast"
      TalentPool.find(cast_id).people
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
    params.require(:questionnaire).permit(:title, :instruction_text, :accepting_responses, :include_availability_section, :require_all_availability, availability_show_ids: [])
  end

  def question_params
    params.require(:question).permit(:text, :question_type, :required, question_options_attributes: [ :id, :text, :_destroy ])
  end
end

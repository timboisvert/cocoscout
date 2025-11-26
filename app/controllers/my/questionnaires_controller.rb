class My::QuestionnairesController < ApplicationController
  allow_unauthenticated_access only: [ :inactive ]

  skip_before_action :show_my_sidebar, only: [ :entry, :form, :submitform, :success, :inactive ]

  before_action :set_questionnaire_and_questions, except: [ :index ]

  def index
    @person = Current.user.person
    @groups = @person.groups.active.order(:name)

    @filter = params[:filter] || "awaiting"

    # Handle entity filter - comma-separated like availability
    @entity_filter = params[:entity] ? params[:entity].split(",") : ([ "person" ] + @groups.map { |g| "group_#{g.id}" })

    # Build questionnaire-entity pairs
    @questionnaire_entity_pairs = []

    # Get all unique questionnaires from selected entities
    questionnaire_ids = []

    if @entity_filter.include?("person")
      person_q_ids = QuestionnaireInvitation.where(invitee: @person).pluck(:questionnaire_id)
      questionnaire_ids += person_q_ids
    end

    @groups.each do |group|
      if @entity_filter.include?("group_#{group.id}")
        group_q_ids = QuestionnaireInvitation.where(invitee: group).pluck(:questionnaire_id)
        questionnaire_ids += group_q_ids
      end
    end

    questionnaires = Questionnaire.where(id: questionnaire_ids.uniq).includes(:production, :questionnaire_invitations, :questionnaire_responses)

    # Build pairs for each questionnaire-entity combination
    questionnaires.each do |questionnaire|
      if @entity_filter.include?("person") && questionnaire.questionnaire_invitations.exists?(invitee: @person)
        @questionnaire_entity_pairs << {
          questionnaire: questionnaire,
          entity_type: "person",
          entity: @person,
          entity_key: "person"
        }
      end

      @groups.each do |group|
        if @entity_filter.include?("group_#{group.id}") && questionnaire.questionnaire_invitations.exists?(invitee: group)
          @questionnaire_entity_pairs << {
            questionnaire: questionnaire,
            entity_type: "group",
            entity: group,
            entity_key: "group_#{group.id}"
          }
        end
      end
    end

    # Apply filter
    if @filter == "awaiting"
      @questionnaire_entity_pairs = @questionnaire_entity_pairs.select do |pair|
        questionnaire = pair[:questionnaire]
        # Only show if: not responded, not archived, and accepting responses
        !questionnaire.questionnaire_responses.exists?(respondent: pair[:entity]) &&
        questionnaire.archived_at.nil? &&
        questionnaire.accepting_responses
      end
    end

    # Sort by questionnaire created_at
    @questionnaire_entity_pairs.sort_by! { |pair| pair[:questionnaire].created_at }.reverse!
  end

  def form
    @person = Current.user.person

    # Check if person is invited directly or through a group
    directly_invited = @questionnaire.questionnaire_invitations.exists?(invitee: @person)
    invited_groups = @questionnaire.questionnaire_invitations.where(invitee_type: "Group", invitee_id: @person.groups.pluck(:id)).map(&:invitee)

    unless directly_invited || invited_groups.any?
      redirect_to my_dashboard_path, alert: "You are not invited to this questionnaire"
      return
    end

    # Determine the respondent based on params or default logic
    if params[:respondent_type].present? && params[:respondent_id].present?
      # User explicitly selected a respondent
      @respondent = params[:respondent_type].constantize.find(params[:respondent_id])

      # Verify the selected respondent is valid
      is_valid = (@respondent == @person && directly_invited) ||
                 (@respondent.is_a?(Group) && invited_groups.include?(@respondent))

      unless is_valid
        redirect_to my_dashboard_path, alert: "Invalid respondent selection"
        return
      end
    elsif directly_invited && invited_groups.empty?
      # Only person is invited
      @respondent = @person
    elsif !directly_invited && invited_groups.one?
      # Only one group is invited
      @respondent = invited_groups.first
    elsif directly_invited && invited_groups.any?
      # Both person and group(s) are invited - default to person
      @respondent = @person
    else
      # Multiple groups invited - default to first
      @respondent = invited_groups.first
    end

    @responding_for_group = @respondent.is_a?(Group)
    @directly_invited = directly_invited
    @invited_groups = invited_groups

    # Check if questionnaire is still accepting responses
    unless @questionnaire.accepting_responses
      redirect_to my_questionnaire_inactive_path(token: @questionnaire.token), status: :see_other
      return
    end

    # Load shows for availability section if enabled
    if @questionnaire.include_availability_section
      @shows = @production.shows.where("date_and_time >= ?", Time.current).order(:date_and_time)

      # Filter by show ids if specified
      if @questionnaire.availability_show_ids.present?
        @shows = @shows.where(id: @questionnaire.availability_show_ids)
      end

      # Load existing availability data for the respondent (person or group)
      @availability = {}
      ShowAvailability.where(available_entity: @respondent, show_id: @shows.pluck(:id)).each do |show_availability|
        @availability["#{show_availability.show_id}"] = show_availability.status.to_s
      end
    end

    # Check if they've already responded
    if @questionnaire.questionnaire_responses.exists?(respondent: @respondent)
      @questionnaire_response = @questionnaire.questionnaire_responses.find_by(respondent: @respondent)
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

    # Check if person is invited directly or through a group
    directly_invited = @questionnaire.questionnaire_invitations.exists?(invitee: @person)
    invited_groups = @questionnaire.questionnaire_invitations.where(invitee_type: "Group", invitee_id: @person.groups.pluck(:id)).map(&:invitee)

    unless directly_invited || invited_groups.any?
      redirect_to my_dashboard_path, alert: "You are not invited to this questionnaire"
      return
    end

    # Determine the respondent from form params
    if params[:respondent_type].present? && params[:respondent_id].present?
      @respondent = params[:respondent_type].constantize.find(params[:respondent_id])

      # Verify the selected respondent is valid
      is_valid = (@respondent == @person && directly_invited) ||
                 (@respondent.is_a?(Group) && invited_groups.include?(@respondent))

      unless is_valid
        redirect_to my_dashboard_path, alert: "Invalid respondent selection"
        return
      end
    else
      # No explicit selection - use default logic
      if directly_invited && invited_groups.empty?
        @respondent = @person
      elsif !directly_invited && invited_groups.one?
        @respondent = invited_groups.first
      else
        # Ambiguous - require explicit selection
        redirect_to my_questionnaire_form_path(token: @questionnaire.token), alert: "Please select who you're responding as"
        return
      end
    end

    @responding_for_group = @respondent.is_a?(Group)
    @directly_invited = directly_invited
    @invited_groups = invited_groups

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
    if @questionnaire.questionnaire_responses.exists?(respondent: @respondent)
      @questionnaire_response = @questionnaire.questionnaire_responses.find_by(respondent: @respondent)

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
      @questionnaire_response = QuestionnaireResponse.new(respondent: @respondent)
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

    # Validate required availability if enabled
    @missing_availability = false
    if @questionnaire.include_availability_section && @questionnaire.require_all_availability
      # Load shows to check (only future dates)
      @shows = @production.shows.where("date_and_time >= ?", Time.current).order(:date_and_time)
      if @questionnaire.availability_show_ids.present?
        @shows = @shows.where(id: @questionnaire.availability_show_ids)
      end

      # Check if all shows have a response
      @shows.each do |show|
        if params[:availability].blank? || params[:availability]["#{show.id}"].blank?
          @missing_availability = true
          break
        end
      end
    end

    # Save availability data if provided
    if params[:availability].present?
      params[:availability].each do |show_id, status|
        next if status.blank?

        show_availability = ShowAvailability.find_or_initialize_by(
          available_entity: @respondent,
          show_id: show_id
        )
        show_availability.status = status
        show_availability.save!
      end
    end

    # Validate and save
    if @missing_required_questions.any? || @missing_availability
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
      redirect_to my_questionnaire_form_path(token: @questionnaire.token), status: :see_other
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
      redirect_to my_questionnaire_form_path(token: params[:token]), status: :see_other
    end
  end
end

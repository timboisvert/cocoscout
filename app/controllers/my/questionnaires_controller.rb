# frozen_string_literal: true

module My
  class QuestionnairesController < ApplicationController
    allow_unauthenticated_access only: [ :inactive ]
    skip_before_action :show_my_sidebar, only: %i[entry form submitform success inactive]
    before_action :set_questionnaire_and_questions, except: [ :index ]

    def index
      @people = Current.user.people.active.order(:created_at).to_a
      people_ids = @people.map(&:id)
      people_by_id = @people.index_by(&:id)

      # Get groups from ALL profiles
      @groups = Group.active.joins(:group_memberships).where(group_memberships: { person_id: people_ids }).distinct.order(:name).to_a

      @filter = params[:filter] || "awaiting"

      # Handle entity filter - comma-separated like availability
      default_entities = @people.map { |p| "person_#{p.id}" } + @groups.map { |g| "group_#{g.id}" }
      @entity_filter = params[:entity] ? params[:entity].split(",") : default_entities

      # Build questionnaire-entity pairs
      @questionnaire_entity_pairs = []

      # Get all unique questionnaires from selected entities
      questionnaire_ids = []

      # Get questionnaire IDs for selected profiles
      selected_person_ids = @people.select { |p| @entity_filter.include?("person_#{p.id}") }.map(&:id)
      if selected_person_ids.any?
        person_q_ids = QuestionnaireInvitation.where(invitee_type: "Person", invitee_id: selected_person_ids).pluck(:questionnaire_id)
        questionnaire_ids += person_q_ids
      end

      @groups.each do |group|
        if @entity_filter.include?("group_#{group.id}")
          group_q_ids = QuestionnaireInvitation.where(invitee: group).pluck(:questionnaire_id)
          questionnaire_ids += group_q_ids
        end
      end

      questionnaires = Questionnaire.where(id: questionnaire_ids.uniq).includes(:production, :questionnaire_invitations,
                                                                                :questionnaire_responses)

      # Build pairs for each questionnaire-entity combination
      questionnaires.each do |questionnaire|
        # Check each selected profile
        selected_person_ids.each do |person_id|
          person = people_by_id[person_id]
          if questionnaire.questionnaire_invitations.exists?(invitee: person)
            @questionnaire_entity_pairs << {
              questionnaire: questionnaire,
              entity_type: "person",
              entity: person,
              entity_key: "person_#{person.id}"
            }
          end
        end

        @groups.each do |group|
          unless @entity_filter.include?("group_#{group.id}") && questionnaire.questionnaire_invitations.exists?(invitee: group)
            next
          end

          @questionnaire_entity_pairs << {
            questionnaire: questionnaire,
            entity_type: "group",
            entity: group,
            entity_key: "group_#{group.id}"
          }
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
      invited_groups = @questionnaire.questionnaire_invitations.where(invitee_type: "Group",
                                                                      invitee_id: @person.groups.pluck(:id)).map(&:invitee)

      unless directly_invited || invited_groups.any?
        redirect_to my_dashboard_path, alert: "You are not invited to this questionnaire"
        return
      end

      # Determine the respondent based on params or default logic
      if params[:respondent_type].present? && params[:respondent_id].present?
        # Validate respondent_type against allowlist before constantize
        allowed_respondent_types = %w[Person Group]
        unless allowed_respondent_types.include?(params[:respondent_type])
          redirect_to my_dashboard_path, alert: "Invalid respondent type"
          return
        end
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

      # Check if they've already responded (within this context)
      if @questionnaire.questionnaire_responses.exists?(respondent: @respondent, context: @context)
        @questionnaire_response = @questionnaire.questionnaire_responses.find_by(respondent: @respondent, context: @context)
        @answers = {}
        @questions.each do |question|
          answer = @questionnaire_response.questionnaire_answers.find_by(question: question)
          @answers[question.id.to_s] = answer.value if answer
        end
      else
        @questionnaire_response = QuestionnaireResponse.new
        @answers = {}
        @questions.each do |question|
          @answers[question.id.to_s] = ""
        end
      end
    end

    def submitform
      @person = Current.user.person

      # Preload person's group IDs to avoid N+1
      person_group_ids = @person.group_ids

      # Check if person is invited directly or through a group
      directly_invited = @questionnaire.questionnaire_invitations.exists?(invitee: @person)
      invited_groups = @questionnaire.questionnaire_invitations
                                     .where(invitee_type: "Group", invitee_id: person_group_ids)
                                     .includes(:invitee)
                                     .map(&:invitee)

      unless directly_invited || invited_groups.any?
        redirect_to my_dashboard_path, alert: "You are not invited to this questionnaire"
        return
      end

      # Determine the respondent from form params
      if params[:respondent_type].present? && params[:respondent_id].present?
        # Validate respondent_type against allowlist before constantize
        allowed_respondent_types = %w[Person Group]
        unless allowed_respondent_types.include?(params[:respondent_type])
          redirect_to my_dashboard_path, alert: "Invalid respondent type"
          return
        end
        @respondent = params[:respondent_type].constantize.find(params[:respondent_id])

        # Verify the selected respondent is valid
        is_valid = (@respondent == @person && directly_invited) ||
                   (@respondent.is_a?(Group) && invited_groups.include?(@respondent))

        unless is_valid
          redirect_to my_dashboard_path, alert: "Invalid respondent selection"
          return
        end
      elsif directly_invited && invited_groups.empty?
        # No explicit selection - use default logic
        @respondent = @person
      elsif !directly_invited && invited_groups.one?
        @respondent = invited_groups.first
      else
        # Ambiguous - require explicit selection
        redirect_to my_questionnaire_form_path(token: @questionnaire.token),
                    alert: "Please select who you're responding as"
        return
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
      organization = @questionnaire.organization
      @person.organizations << organization unless @person.organization_ids.include?(organization.id)

      # Preload questions by ID for efficient lookup
      questions_by_id = @questions.index_by(&:id)

      # Check if updating existing response (within this context)
      existing_response = @questionnaire.questionnaire_responses.find_by(respondent: @respondent, context: @context)

      if existing_response
        @questionnaire_response = existing_response

        # Preload existing answers for this response
        existing_answers = @questionnaire_response.questionnaire_answers.index_by(&:question_id)

        # Update the answers
        @answers = {}
        params[:question]&.each do |id, keyValue|
          question_id = id.to_i
          answer = existing_answers[question_id] || @questionnaire_response.questionnaire_answers.build(question: questions_by_id[question_id])
          answer.value = keyValue
          answer.save!
          @answers[id.to_s] = answer.value
        end

        # Handle file uploads for file_upload questions
        params[:file_upload]&.each do |id, file|
          question_id = id.to_i
          next unless file.present? && questions_by_id[question_id]&.question_type == "file_upload"

          answer = existing_answers[question_id] || @questionnaire_response.questionnaire_answers.find_or_create_by!(question: questions_by_id[question_id])
          answer.file.attach(file)
          answer.value = file.original_filename
          answer.save!
          @answers[id.to_s] = answer.value
        end
      else
        # New response
        @questionnaire_response = QuestionnaireResponse.new(respondent: @respondent, context: @context)
        @questionnaire_response.questionnaire = @questionnaire

        # Loop through the questions and store the answers
        @answers = {}
        params[:question]&.each do |question|
          question_id = question.first.to_i
          answer = @questionnaire_response.questionnaire_answers.build
          answer.question = questions_by_id[question_id]
          answer.value = question.last
          @answers[answer.question.id.to_s] = answer.value
        end
      end

      # Validate required questions
      @missing_required_questions = []
      @questions.select(&:required).each do |question|
        answer_value = @answers[question.id.to_s]

        if question.question_type == "file_upload"
          # For file uploads, check if a file was uploaded (new or existing)
          has_file = params.dig(:file_upload, question.id.to_s).present?
          has_existing = existing_response && existing_response.questionnaire_answers.find_by(question: question)&.file&.attached?
          @missing_required_questions << question unless has_file || has_existing
        elsif answer_value.blank? || (answer_value.is_a?(Hash) && answer_value.values.all?(&:blank?))
          @missing_required_questions << question
        end
      end

      # Validate and save
      if @missing_required_questions.any?
        render :form, status: :unprocessable_entity
      elsif @questionnaire_response.valid?
        @questionnaire_response.save!

        # Attach files for new responses (after save so answer records have IDs)
        if existing_response.nil?
          params[:file_upload]&.each do |id, file|
            question_id = id.to_i
            next unless file.present? && questions_by_id[question_id]&.question_type == "file_upload"

            answer = @questionnaire_response.questionnaire_answers.find_by(question_id: question_id)
            if answer
              answer.file.attach(file)
              answer.update!(value: file.original_filename)
            end
          end
        end

        redirect_to my_questionnaire_success_path(token: @questionnaire.token), status: :see_other
      else
        render :form
      end
    end

    def success; end

    def inactive
      return unless @questionnaire.accepting_responses && params[:force].blank?

      redirect_to my_questionnaire_form_path(token: @questionnaire.token), status: :see_other
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
      resolve_context
    end

    ALLOWED_CONTEXT_TYPES = %w[CourseOffering Show Production].freeze

    def resolve_context
      @context = nil
      return if params[:ctx].blank?

      type, id = params[:ctx].split("-", 2)
      return unless type.in?(ALLOWED_CONTEXT_TYPES) && id.present?

      @context = type.constantize.find_by(id: id)
    end

    def ensure_user_is_signed_in
      return if authenticated?

      redirect_to my_questionnaire_form_path(token: params[:token]), status: :see_other
    end
  end
end

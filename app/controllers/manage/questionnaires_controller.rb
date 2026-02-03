# frozen_string_literal: true

module Manage
  class QuestionnairesController < Manage::ManageController
    before_action :set_production, except: [ :select_production, :save_production_selection, :org_index ]
    before_action :set_questionnaire,
                  only: %i[show update archive unarchive form preview create_question update_question destroy_question reorder_questions
                           responses show_response invite_people]

    # Org-level index showing all questionnaires across productions
    def org_index
      @filter = params[:filter] || "all"

      @questionnaires_by_production = Current.organization.productions
        .includes(:questionnaires)
        .order(:name)
        .map do |prod|
          questionnaires = case @filter
          when "accepting"
            prod.questionnaires.where(archived_at: nil, accepting_responses: true).order(created_at: :desc)
          when "archived"
            prod.questionnaires.where.not(archived_at: nil).order(archived_at: :desc)
          else # 'all'
            prod.questionnaires.where(archived_at: nil).order(created_at: :desc)
          end

          [ prod, questionnaires ]
        end
        .reject { |_prod, questionnaires| questionnaires.empty? }
    end

    # Step 0: Select Production (when entering from org-level)
    def select_production
      @productions = Current.organization.productions.order(:name)
    end

    def save_production_selection
      production_id = params[:production_id]

      if production_id.blank?
        flash.now[:alert] = "Please select a production"
        @productions = Current.organization.productions.order(:name)
        render :select_production, status: :unprocessable_entity and return
      end

      production = Current.organization.productions.find_by(id: production_id)
      unless production
        flash.now[:alert] = "Production not found"
        @productions = Current.organization.productions.order(:name)
        render :select_production, status: :unprocessable_entity and return
      end

      # Redirect to the production-level new questionnaire page
      redirect_to manage_new_casting_questionnaire_path(production)
    end

    def index
      @filter = params[:filter] || "all"

      case @filter
      when "accepting"
        @questionnaires = @production.questionnaires.where(archived_at: nil,
                                                           accepting_responses: true).order(created_at: :desc)
      when "archived"
        @questionnaires = @production.questionnaires.where.not(archived_at: nil).order(archived_at: :desc)
      else # 'all'
        @questionnaires = @production.questionnaires.where(archived_at: nil).order(created_at: :desc)
      end
    end

    def show
      @questions = @questionnaire.questions.order(:position)

      # Create email draft for invitation form
      @questionnaire_email_draft = EmailDraft.new(
        title: default_questionnaire_email_subject,
        body: default_questionnaire_email_body
      )
    end

    def new
      @questionnaire = @production.questionnaires.new
    end

    def create
      @questionnaire = @production.questionnaires.new(questionnaire_params)

      if @questionnaire.save
        redirect_to manage_form_casting_questionnaire_path(@production, @questionnaire),
                    notice: "Questionnaire created successfully"
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
              redirect_to manage_form_casting_questionnaire_path(@production, @questionnaire),
                          notice: "Questionnaire updated successfully"
            else
              redirect_to manage_casting_questionnaire_path(@production, @questionnaire),
                          notice: "Questionnaire updated successfully"
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
      redirect_to manage_casting_questionnaires_path(@production), notice: "Questionnaire archived successfully"
    end

    def unarchive
      @questionnaire.update(archived_at: nil)
      redirect_to manage_casting_questionnaire_path(@production, @questionnaire),
                  notice: "Questionnaire unarchived successfully"
    end

    def form
      @questions = @questionnaire.questions.order(:position)
      @shows = @production.shows.where("date_and_time >= ?", Time.current).order(:date_and_time)

      # Check if we're editing a specific question
      @question = if params[:question_id].present?
                    @questionnaire.questions.find(params[:question_id])
      else
                    @questionnaire.questions.new
      end
    end

    def preview
      @questions = @questionnaire.questions.order(:position)

      # Load shows for availability section if enabled
      return unless @questionnaire.include_availability_section

      @shows = @production.shows.where("date_and_time >= ?", Time.current).order(:date_and_time)

      # Filter shows by selected show IDs if specified
      return unless @questionnaire.availability_show_ids.present?

      @shows = @shows.where(id: @questionnaire.availability_show_ids)
    end

    def create_question
      @question = @questionnaire.questions.new(question_params)

      # Set position as the last question
      max_position = @questionnaire.questions.maximum(:position) || 0
      @question.position = max_position + 1

      if @question.save
        redirect_to manage_form_casting_questionnaire_path(@production, @questionnaire),
                    notice: "Question added successfully"
      else
        @questions = @questionnaire.questions.order(:position)
        render :form, status: :unprocessable_entity
      end
    end

    def update_question
      @question = @questionnaire.questions.find(params[:question_id])

      if @question.update(question_params)
        redirect_to manage_form_casting_questionnaire_path(@production, @questionnaire),
                    notice: "Question updated successfully"
      else
        @questions = @questionnaire.questions.order(:position)
        render :form, status: :unprocessable_entity
      end
    end

    def destroy_question
      @question = @questionnaire.questions.find(params[:question_id])
      @question.destroy
      redirect_to manage_form_casting_questionnaire_path(@production, @questionnaire),
                  notice: "Question deleted successfully"
    end

    def reorder_questions
      params[:question_ids].each_with_index do |id, index|
        @questionnaire.questions.find(id).update(position: index + 1)
      end

      head :ok
    end

    def responses
      @responses = @questionnaire.questionnaire_responses
                                 .includes(:respondent)
                                 .order(created_at: :desc)
    end

    def show_response
      @response = @questionnaire.questionnaire_responses.find(params[:response_id])
      @questions = @questionnaire.questions.order(:position)
      @answers = {}
      @questions.each do |question|
        answer = @response.questionnaire_answers.find_by(question: question)
        @answers[question.id.to_s] = answer.value if answer
      end

      # Load availability data if enabled
      if @questionnaire.include_availability_section
        @shows = @production.shows.where("date_and_time >= ?", Time.current).order(:date_and_time)

        # Filter by show ids if specified
        @shows = @shows.where(id: @questionnaire.availability_show_ids) if @questionnaire.availability_show_ids.present?

        # Load availability data for this respondent (person or group)
        @availability = {}
        ShowAvailability.where(available_entity: @response.respondent,
                               show_id: @shows.pluck(:id)).each do |show_availability|
          @availability[show_availability.show_id.to_s] = show_availability.status.to_s
        end
      end

      render :response
    end

    def invite_people
      recipient_type = params[:recipient_type]
      talent_pool_id = params[:talent_pool_id]
      person_ids = params[:person_ids] || []
      group_ids = params[:group_ids] || []

      # Get email content from EmailDraft form fields
      email_draft_params = params[:email_draft] || {}
      subject_template = email_draft_params[:title].presence || default_questionnaire_email_subject
      message_template = email_draft_params[:body].to_s.presence || default_questionnaire_email_body

      # Get IDs of already invited people and groups
      already_invited_person_ids = @questionnaire.questionnaire_invitations
                                                 .where(invitee_type: "Person").pluck(:invitee_id)
      already_invited_group_ids = @questionnaire.questionnaire_invitations
                                                .where(invitee_type: "Group").pluck(:invitee_id)

      # Get all people and groups in the production's effective talent pool
      talent_pool = @production.effective_talent_pool
      all_people = talent_pool&.people&.to_a || []
      all_groups = talent_pool&.groups&.to_a || []

      # Filter to only those not yet invited
      not_invited_people = all_people.reject { |p| already_invited_person_ids.include?(p.id) }
      not_invited_groups = all_groups.reject { |g| already_invited_group_ids.include?(g.id) }

      # Determine person and group recipients based on recipient_type
      person_recipients = []
      group_recipients = []

      case recipient_type
      when "all"
        # Only send to those NOT yet invited
        person_recipients = not_invited_people
        group_recipients = not_invited_groups
      when "cast"
        talent_pool = TalentPool.find(talent_pool_id)
        # Only send to those in the talent pool who are NOT yet invited
        person_recipients = talent_pool.people.reject { |p| already_invited_person_ids.include?(p.id) }
        group_recipients = talent_pool.groups.reject { |g| already_invited_group_ids.include?(g.id) }
      when "specific"
        # For specific selection, only include those not yet invited
        person_recipients = Person.where(id: person_ids).reject { |p| already_invited_person_ids.include?(p.id) }
        group_recipients = Group.where(id: group_ids).reject { |g| already_invited_group_ids.include?(g.id) }
      end

      invitation_count = 0

      # Calculate total email recipients for batch creation
      email_recipients_count = person_recipients.count { |p| p.user.present? }
      group_recipients.each do |group|
        email_recipients_count += group.group_memberships.select(&:notifications_enabled?).count { |m| m.person.user.present? }
      end

      # Create email batch if sending to multiple people
      email_batch = nil
      if email_recipients_count > 1
        email_batch = EmailBatch.create!(
          user: Current.user,
          subject: subject_template,
          recipient_count: email_recipients_count,
          sent_at: Time.current
        )
      end

      # Create invitations for people and send emails
      person_recipients.each do |person|
        QuestionnaireInvitation.create!(
          questionnaire: @questionnaire,
          invitee: person
        )
        invitation_count += 1

        # Send email if person has a user account
        if person.user
          Manage::QuestionnaireMailer.invitation(person, @questionnaire, @production, subject_template,
                                                 message_template, email_batch_id: email_batch&.id).deliver_later
        end
      end

      # Create invitations for groups and send to members with notifications enabled
      group_recipients.each do |group|
        QuestionnaireInvitation.create!(
          questionnaire: @questionnaire,
          invitee: group
        )
        invitation_count += 1

        # Send emails to all group members with notifications enabled
        members_with_notifications = group.group_memberships.select(&:notifications_enabled?).map(&:person)
        members_with_notifications.each do |person|
          if person.user
            Manage::QuestionnaireMailer.invitation(person, @questionnaire, @production, subject_template,
                                                   message_template, email_batch_id: email_batch&.id).deliver_later
          end
        end
      end

      redirect_to manage_casting_questionnaire_path(@production, @questionnaire),
                  notice: "Invited #{invitation_count} #{'member'.pluralize(invitation_count)}"
    end

    private

    def set_production
      unless Current.organization
        redirect_to select_organization_path, alert: "Please select an organization first."
        return
      end
      @production = Current.organization.productions.find(params[:production_id])
      sync_current_production(@production)
    end

    def set_questionnaire
      @questionnaire = @production.questionnaires.find(params[:id])
    end

    def questionnaire_params
      params.require(:questionnaire).permit(:title, :instruction_text, :accepting_responses,
                                            :include_availability_section, :require_all_availability, availability_show_ids: [])
    end

    def question_params
      params.require(:question).permit(:text, :question_type, :required,
                                       question_options_attributes: %i[id text _destroy])
    end

    def default_questionnaire_email_subject
      ContentTemplateService.render_subject("questionnaire_invitation", {
        production_name: @production.name,
        questionnaire_title: @questionnaire.title
      })
    end

    def default_questionnaire_email_body
      ContentTemplateService.render_body("questionnaire_invitation", {
        production_name: @production.name,
        questionnaire_title: @questionnaire.title,
        questionnaire_url: @questionnaire.respond_url
      })
    end
  end
end

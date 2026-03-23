# frozen_string_literal: true

module Manage
  class QuestionnairesController < Manage::ManageController
    before_action :set_questionnaire,
                  only: %i[show update archive unarchive form preview create_question update_question destroy_question reorder_questions
                           responses responses_table show_response invite_people]

    def index
      @filter = params[:filter] || "all"

      base = Current.organization.questionnaires
      @questionnaires = case @filter
      when "accepting"
        base.where(archived_at: nil, accepting_responses: true).order(created_at: :desc)
      when "archived"
        base.where.not(archived_at: nil).order(archived_at: :desc)
      else # 'all'
        base.where(archived_at: nil).order(created_at: :desc)
      end
    end

    def show
      @questions = @questionnaire.questions.order(:position)
      @linked_course_offerings = @questionnaire.course_offerings.includes(:production)

      # Create email draft for invitation form (only needed when no course delivery)
      @questionnaire_email_draft = EmailDraft.new(
        title: default_questionnaire_email_subject,
        body: default_questionnaire_email_body
      )
    end

    def new
      @questionnaire = Current.organization.questionnaires.new
      @questionnaire.title = params[:title] if params[:title].present?
    end

    def create
      @questionnaire = Current.organization.questionnaires.new(questionnaire_params)

      if @questionnaire.save
        redirect_to manage_form_contacts_questionnaire_path(@questionnaire),
                    notice: "Questionnaire created successfully"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      params_to_update = questionnaire_params

      if @questionnaire.update(params_to_update)
        respond_to do |format|
          format.html do
            # If updating from the form page (title or instruction), redirect back to form
            if params[:questionnaire]&.key?(:title) ||
               params[:questionnaire]&.key?(:instruction_text)
              redirect_to manage_form_contacts_questionnaire_path(@questionnaire),
                          notice: "Questionnaire updated successfully"
            else
              redirect_to manage_contacts_questionnaire_path(@questionnaire),
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
      redirect_to manage_contacts_questionnaires_path, notice: "Questionnaire archived successfully"
    end

    def unarchive
      @questionnaire.update(archived_at: nil)
      redirect_to manage_contacts_questionnaire_path(@questionnaire),
                  notice: "Questionnaire unarchived successfully"
    end

    def form
      @questions = @questionnaire.questions.order(:position)

      # Check if we're editing a specific question
      @question = if params[:question_id].present?
                    @questionnaire.questions.find(params[:question_id])
      else
                    @questionnaire.questions.new
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
        redirect_to manage_form_contacts_questionnaire_path(@questionnaire, questions_open: true),
                    notice: "Question added successfully"
      else
        @questions = @questionnaire.questions.order(:position)
        render :form, status: :unprocessable_entity
      end
    end

    def update_question
      @question = @questionnaire.questions.find(params[:question_id])

      if @question.update(question_params)
        redirect_to manage_form_contacts_questionnaire_path(@questionnaire, questions_open: true),
                    notice: "Question updated successfully"
      else
        @questions = @questionnaire.questions.order(:position)
        render :form, status: :unprocessable_entity
      end
    end

    def destroy_question
      @question = @questionnaire.questions.find(params[:question_id])
      @question.destroy
      redirect_to manage_form_contacts_questionnaire_path(@questionnaire, questions_open: true),
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

    def responses_table
      @questions = @questionnaire.questions.order(:position)
      @responses = @questionnaire.questionnaire_responses
                                 .includes(:respondent, questionnaire_answers: { file_attachment: :blob })
                                 .order(created_at: :desc)

      # Build matrix: { response_id => { question_id => answer_object } }
      @answers_matrix = {}
      @responses.each do |response|
        @answers_matrix[response.id] = response.questionnaire_answers.index_by(&:question_id)
      end
    end

    def show_response
      @response = @questionnaire.questionnaire_responses.find(params[:response_id])
      @questions = @questionnaire.questions.order(:position)
      @answers = {}
      @answer_objects = {}
      @questions.each do |question|
        answer = @response.questionnaire_answers.includes(file_attachment: :blob).find_by(question: question)
        if answer
          @answers[question.id.to_s] = answer.value
          @answer_objects[question.id.to_s] = answer
        end
      end

      render :response
    end

    def invite_people
      person_ids = params[:person_ids] || []

      # Get email content from EmailDraft form fields
      email_draft_params = params[:email_draft] || {}
      custom_subject = email_draft_params[:title].presence
      custom_body = email_draft_params[:body].to_s.presence

      # Get IDs of already invited people
      already_invited_person_ids = @questionnaire.questionnaire_invitations
                                                 .where(invitee_type: "Person").pluck(:invitee_id).to_set

      # Only include people not yet invited, scoped to the organization
      person_recipients = Current.organization.people
                                              .where(id: person_ids)
                                              .reject { |p| already_invited_person_ids.include?(p.id) }

      invitation_count = 0

      # Create invitations for people and send messages
      person_recipients.each do |person|
        QuestionnaireInvitation.create!(
          questionnaire: @questionnaire,
          invitee: person
        )
        invitation_count += 1

        # Send in-app message if person has a user account
        if person.user
          questionnaire_url = Rails.application.routes.url_helpers.my_questionnaire_form_url(
            token: @questionnaire.token,
            host: ENV.fetch("HOST", "localhost:3000")
          )

          variables = {
            person_name: person.first_name || "there",
            questionnaire_title: @questionnaire.title,
            questionnaire_url: questionnaire_url
          }

          if custom_subject.present? && custom_body.present?
            # Use customized content with variable interpolation
            subject = custom_subject
            body = custom_body.gsub("{{questionnaire_url}}", questionnaire_url)
                              .gsub("{{person_name}}", person.first_name || "there")
                              .gsub("{{questionnaire_title}}", @questionnaire.title)
          else
            rendered = ContentTemplateService.render("questionnaire_invitation", variables)
            subject = rendered[:subject]
            body = rendered[:body]
          end

          MessageService.send_direct(
            sender: Current.user,
            recipient_person: person,
            subject: subject,
            body: body,
            organization: Current.organization
          )
        end
      end

      redirect_to manage_contacts_questionnaire_path(@questionnaire),
                  notice: "Invited #{invitation_count} #{'person'.pluralize(invitation_count)}"
    end

    private

    def set_questionnaire
      @questionnaire = Current.organization.questionnaires.find(params[:id])
    end

    def questionnaire_params
      params.require(:questionnaire).permit(:title, :instruction_text, :accepting_responses)
    end

    def question_params
      params.require(:question).permit(:text, :question_type, :required,
                                       question_options_attributes: %i[id text _destroy])
    end

    def default_questionnaire_email_subject
      ContentTemplateService.render_subject("questionnaire_invitation", {
        questionnaire_title: @questionnaire.title
      })
    end

    def default_questionnaire_email_body
      ContentTemplateService.render_body("questionnaire_invitation", {
        questionnaire_title: @questionnaire.title,
        questionnaire_url: @questionnaire.respond_url
      })
    end
  end
end

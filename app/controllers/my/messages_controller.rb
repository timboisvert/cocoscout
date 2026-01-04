# frozen_string_literal: true

module My
  class MessagesController < ApplicationController
    before_action :require_authentication
    def index
      @show_my_sidebar = true
      # Load emails sent to the current user's person
      person = Current.user.person
      return redirect_to my_dashboard_path, alert: "No profile found." unless person

      # Get emails sent to this person (across all organizations)
      email_logs_query = EmailLog.for_recipient_entity(person).recent

      if params[:search].present?
        search_term = "%#{params[:search]}%"
        email_logs_query = email_logs_query.where("subject ILIKE ?", search_term)
      end

      @email_logs_pagy, @email_logs = pagy(email_logs_query.includes(:production), limit: 20)
      @search_query = params[:search]

      # For the send message modal - create empty email draft
      @email_draft = EmailDraft.new

      # Get all productions the user is in the talent pool of (across all organizations)
      @my_productions = Current.user.person.talent_pool_productions
                                    .includes(:organization)
                                    .order(:name)
    end

    def show
      @show_my_sidebar = true
      person = Current.user.person
      return redirect_to my_dashboard_path, alert: "No profile found." unless person

      @email_log = EmailLog.for_recipient_entity(person).find_by(id: params[:id])

      unless @email_log
        redirect_to my_messages_path, alert: "Message not found."
      end
    end

    def send_message
      production_id = params[:production_id]
      @email_draft = EmailDraft.new(email_draft_params)
      subject = @email_draft.title
      body_html = @email_draft.body.to_s

      # Prepare variables for the template
      template_vars = {
        sender_name: Current.user.person.name,
        sender_email: Current.user.person.email,
        production_name: production&.name,
        body_html: body_html,
        subject: subject
      }

      # Render subject and body using the passthrough template
      rendered_subject = EmailTemplateService.render_subject("talent_pool_message", template_vars)
      rendered_body = EmailTemplateService.render_body("talent_pool_message", template_vars)

      if production_id.blank?
        redirect_to my_messages_path, alert: "Please select a production to contact."
        return
      end

      production = Production.find_by(id: production_id)
      unless production
        redirect_to my_messages_path, alert: "Production not found."
        return
      end

      # Verify the user is in the talent pool of this production
      unless Current.user.person.in_talent_pool_for?(production)
        redirect_to my_messages_path, alert: "You are not a member of this production's talent pool."
        return
      end

      # Send to production email address
      production_email = production.contact_email
      if production_email.blank?
        redirect_to my_messages_path, alert: "This production does not have a contact email address configured."
        return
      end


      # Send the email to the production
      My::TalentMessageMailer.send_to_production(
        sender: Current.user.person,
        production: production,
        subject: rendered_subject,
        body_html: rendered_body
      ).deliver_later

      redirect_to my_messages_path,
                  notice: "Message sent to #{production.name} team."
    end

    private

    def email_draft_params
      params.require(:email_draft).permit(:title, :body)
    end
  end
end

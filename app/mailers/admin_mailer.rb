# frozen_string_literal: true

class AdminMailer < ApplicationMailer
  def user_account_created(user)
    @user = user
    @person = user.primary_person

    # Get the email template
    template = EmailTemplate.find_by(key: "user_account_created")

    # Prepare variables for template rendering
    variables = {
      user_email: @user.email_address,
      user_id: @user.id,
      created_at: @user.created_at.strftime("%B %d, %Y at %I:%M %p %Z"),
      person_name: @person&.name || "No person profile yet",
      admin_url: Rails.application.routes.url_helpers.superadmin_url(host: ENV.fetch("HOST", "localhost:3000"))
    }

    # Render the template
    @subject = template.render_subject(variables)
    @body = template.render_body(variables)

    # Send to all superadmins who have accounts
    superadmin_emails = User.where("LOWER(email_address) IN (?)", User::SUPERADMIN_EMAILS.map(&:downcase)).pluck(:email_address)

    mail(
      to: superadmin_emails,
      subject: @subject
    ) do |format|
      format.html { render html: @body.html_safe }
    end
  end
end

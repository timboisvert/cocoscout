# frozen_string_literal: true

# Consolidated mailer for all application emails.
# Uses ContentTemplateService to render templates.
#
# This replaces all individual mailers with a single, unified mailer.
#
# Usage:
#   AppMailer.with(
#     template_key: "auth_welcome",
#     to: user.email_address,
#     variables: { user_email: user.email_address }
#   ).send_template.deliver_later
#
class AppMailer < ApplicationMailer
  # Generic template-based email sender
  def send_template
    @template_key = params[:template_key]
    @to = params[:to]
    @variables = params[:variables] || {}
    @email_batch_id = params[:email_batch_id]

    # Render the template
    rendered = ContentTemplateService.render(@template_key, @variables)
    @subject = rendered[:subject]
    @body = rendered[:body]

    headers["X-Email-Batch-ID"] = @email_batch_id.to_s if @email_batch_id.present?

    mail(to: @to, subject: @subject) do |format|
      format.html { render html: @body.html_safe, layout: "mailer" }
    end
  end
end

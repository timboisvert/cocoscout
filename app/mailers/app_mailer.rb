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
    # An email that is itself about the app leaves the footer's line about it off.
    @hide_app_note = params[:hide_app_note]

    # Images attached to the email itself, as { "variable" => path }: each is
    # attached inline and its cid: address handed to the template as
    # "<variable>_src" (the app email's store badges).
    Hash(params[:inline_images]).each do |name, path|
      filename = File.basename(path.to_s)
      attachments.inline[filename] = File.binread(path)
      @variables = @variables.merge("#{name}_src" => attachments[filename].url)
    end

    # Render the template
    rendered = ContentTemplateService.render(@template_key, @variables)
    @subject = rendered[:subject]
    @body = rendered[:body]

    headers["X-Email-Batch-ID"] = @email_batch_id.to_s if @email_batch_id.present?
    # PDFs to attach, as { "filename.pdf" => bytes } (deliver_now only: the
    # bytes don't go through a job queue).
    Hash(params[:attachments]).each do |filename, content|
      attachments[filename] = { mime_type: "application/pdf", content: content }
    end

    mail(to: @to, subject: @subject) do |format|
      format.html { render html: @body.html_safe, layout: "mailer" }
    end
  end
end

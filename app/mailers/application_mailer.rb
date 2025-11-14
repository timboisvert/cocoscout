class ApplicationMailer < ActionMailer::Base
  default from: "no-reply@cocoscout.com"
  layout "mailer"

  before_action :attach_logo

  private

  def attach_logo
    attachments.inline["cocoscout.png"] = File.read(Rails.root.join("app", "assets", "images", "cocoscout.png"))
  end

  # Override mail method to add user tracking headers
  def mail(headers = {}, &block)
    user = find_user_from_params

    if user
      # Validate recipient email before sending
      recipient_email = headers[:to] || user.email_address
      unless recipient_email.to_s.match?(URI::MailTo::EMAIL_REGEXP)
        Rails.logger.error("Attempted to send email to invalid address: #{recipient_email}")
        return # Don't send email with invalid recipient
      end

      headers["X-User-ID"] = user.id.to_s
      headers["X-Mailer-Class"] = self.class.name
      headers["X-Mailer-Action"] = action_name
    end

    super(headers, &block)
  end

  def find_user_from_params
    # Check common instance variables for user object (recipient, not sender)
    # Use &. safe navigation to avoid NoMethodError
    @user ||
      @person&.user ||
      @team_invitation&.user ||
      (@person_invitation && Person.find_by(email: @person_invitation.email)&.user) ||
      @sender
  end
end

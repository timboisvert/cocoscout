# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: "info@cocoscout.com"
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

    # Add recipient entity tracking for email logs
    recipient_entity = find_recipient_entity
    if recipient_entity
      headers["X-Recipient-Entity-Type"] = recipient_entity.class.name
      headers["X-Recipient-Entity-ID"] = recipient_entity.id.to_s
    end

    # Add email batch ID if set via params, instance method, or thread-local storage
    batch_id = params[:email_batch_id] ||
               (respond_to?(:find_email_batch_id, true) ? find_email_batch_id : nil) ||
               Thread.current[:email_batch_id]
    if batch_id
      headers["X-Email-Batch-ID"] = batch_id.to_s
    end

    # Add organization ID for scoping email logs
    organization = find_organization
    if organization
      headers["X-Organization-ID"] = organization.id.to_s
    end

    super(headers, &block)
  end

  def find_user_from_params
    # Check common instance variables for user object (recipient, not sender)
    # Use &. safe navigation to avoid NoMethodError
    # Note: For invitations, the user might not exist yet, which is fine
    @user ||
      @person&.user ||
      (@team_invitation && User.find_by(email_address: @team_invitation.email)) ||
      (@person_invitation && Person.find_by(email: @person_invitation.email)&.user) ||
      @sender
  end

  def find_recipient_entity
    # Find the recipient entity (Person or Group) from instance variables
    # Check @user.person as fallback for mailers that only set @user
    @person || @group || @recipient || @user&.person
  end

  def find_organization
    # Find the organization from instance variables or through associations
    # Check direct instance variable first, then look through related objects
    @organization ||
      @show&.production&.organization ||
      @production&.organization ||
      @person&.organizations&.first ||
      @group&.organization ||
      @team_invitation&.organization ||
      Current.organization
  end
end

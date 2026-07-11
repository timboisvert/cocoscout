# frozen_string_literal: true

# Invites a staff member to finish onboarding: ensures they have a CocoScout
# account, sends BOTH an onboarding email (focused on setting up how they get
# paid) and a parallel in-app message, and marks the membership as "invited".
#
# Shared by the add-staff wizard (auto-invite on add) and the manual
# invite/resend button on the staff list.
class StaffOnboardingInviter
  include Rails.application.routes.url_helpers

  class Error < StandardError; end

  def self.call(...)
    new(...).call
  end

  # Build the interpolated onboarding email/message without sending anything —
  # used to preview the exact draft before an org confirms the send.
  def self.preview(staff_member:)
    new(staff_member: staff_member, sender: nil).preview
  end

  # sender: the User performing the invite (for the in-app message's From).
  def initialize(staff_member:, sender:)
    @staff_member = staff_member
    @organization = staff_member.organization
    @person = staff_member.person
    @sender = sender
  end

  def preview
    onboarding_copy.merge(to_name: @person&.name, to_email: recipient_email.presence)
  end

  def call
    email = recipient_email
    raise Error, "#{@person.name} has no email on file — add one before inviting them." unless email.match?(URI::MailTo::EMAIL_REGEXP)

    ActiveRecord::Base.transaction do
      ensure_account(email)
      ensure_invitation(email)
      @staff_member.update!(onboarding_state: "invited")
    end

    StaffOnboardingMailer.invite(@staff_member).deliver_later
    send_in_app_message
    @staff_member
  end

  private

  def ensure_account(email)
    return if @person.user.present?

    user = User.find_by(email_address: email) ||
           User.create!(email_address: email, password: User.generate_secure_password)
    @person.update!(user: user)
  end

  def ensure_invitation(email)
    return if PersonInvitation.pending.exists?(email: email, organization: @organization)

    PersonInvitation.create!(email: email, organization: @organization)
  end

  def send_in_app_message
    copy = onboarding_copy
    MessageService.send_direct(
      sender: @sender,
      recipient_person: @person,
      subject: copy[:subject],
      body: copy[:body],
      organization: @organization,
      system_generated: true
    )
  end

  # The single source of truth for the onboarding subject + body, interpolated
  # for this member. Used both for what we send and for the preview draft.
  def onboarding_copy
    first = @staff_member.preferred_first_name.presence ||
            @staff_member.first_name.presence ||
            @person&.first_name.presence || "there"
    setup_url = my_payments_setup_url(**default_url_options)

    if ContentTemplateService.exists?("staff_onboarding_invite")
      rendered = ContentTemplateService.render("staff_onboarding_invite", {
        first_name: first,
        organization_name: @organization.name,
        onboarding_url: setup_url
      })
      { subject: rendered[:subject], body: rendered[:body] }
    else
      { subject: "Finish setting up how you get paid at #{@organization.name}",
        body: <<~HTML }
          <p>Hi #{first},</p>
          <p>You've been added to the team at <strong>#{@organization.name}</strong>. To make sure you get paid, set up how you'd like to receive your money — it only takes a minute.</p>
          <p><a href="#{setup_url}">Set up how you get paid →</a></p>
          <p>You'll connect a bank account so payments land automatically and securely.</p>
        HTML
    end
  end

  def recipient_email
    (@person&.email.presence || @staff_member.personal_email).to_s.strip.downcase
  end

  def default_url_options
    ActionMailer::Base.default_url_options
  end
end

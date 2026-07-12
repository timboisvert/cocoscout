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
  # subject/body: optional overrides (e.g. the reviewer edited the draft).
  def initialize(staff_member:, sender:, subject: nil, body: nil)
    @staff_member = staff_member
    @organization = staff_member.organization
    @person = staff_member.person
    @sender = sender
    @subject_override = subject.to_s.strip.presence
    @body_override = body.to_s.strip.presence
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

    copy = onboarding_copy
    StaffOnboardingMailer.invite(@staff_member, subject: copy[:subject], body: copy[:body]).deliver_later
    send_in_app_message(copy)
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

  def send_in_app_message(copy = onboarding_copy)
    MessageService.send_direct(
      sender: @sender,
      recipient_person: @person,
      subject: copy[:subject],
      body: copy[:body],
      organization: @organization,
      system_generated: true
    )
  end

  # The subject + body actually used — the reviewer's edits if they made any,
  # otherwise the interpolated default.
  def onboarding_copy
    default = default_onboarding_copy
    { subject: @subject_override || default[:subject], body: @body_override || default[:body] }
  end

  # The single source of truth for the default (interpolated) onboarding copy.
  # Used for the preview draft and as the fallback when not overridden.
  def default_onboarding_copy
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
      { subject: "Complete your onboarding at #{@organization.name}",
        body: <<~HTML }
          <p>Hi #{first},</p>
          <p>You've been added to the team at <strong>#{@organization.name}</strong>. Finish your onboarding to get set up — you'll confirm your details (like your legal and preferred names) and set up your payment details so you get paid automatically. It only takes a minute.</p>
          <p><a href="#{setup_url}">Complete onboarding and set up payment details →</a></p>
          <p>Your payment details stay secure with our payment processor.</p>
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

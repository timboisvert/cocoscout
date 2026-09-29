# frozen_string_literal: true

# Asks a staff member for their Form W-9: an email plus a parallel in-app
# message, both pointing at their W-9 page, and stamps w9_requested_at so the
# Taxes page shows when they were asked.
#
# Mirrors StaffOnboardingInviter: `.preview` builds the exact draft (so a
# manager can edit it in the invite-preview modal), and the copy always comes
# from a content template — "staff_w9_request", or "staff_w9_reminder" for the
# scheduled nudges. Never inline copy.
class StaffW9Requester
  include Rails.application.routes.url_helpers

  class Error < StandardError; end

  def self.call(...)
    new(...).call
  end

  def self.preview(staff_member:)
    new(staff_member: staff_member, sender: nil).preview
  end

  # The one draft for asking several people at once: the request copy with
  # {{first_name}} left in, which each send fills with that person's name.
  def self.bulk_draft(organization:)
    rendered = ContentTemplateService.render("staff_w9_request", shared_variables(organization))
    { subject: rendered[:subject], body: rendered[:body] }
  end

  def self.shared_variables(organization)
    {
      organization_name: organization.name,
      w9_url: Rails.application.routes.url_helpers.my_w9_url(organization.id, **ActionMailer::Base.default_url_options)
    }
  end

  # Only people who can sign in can fill the W-9 in (it's behind their
  # account). Someone who hasn't set one up yet gets it as part of onboarding.
  def self.requestable?(staff_member)
    staff_member.person&.user.present? && new(staff_member: staff_member, sender: nil).send(:recipient_email).present?
  end

  # reminder: true sends the gentler follow-up copy and stamps the reminder time
  # instead of the request time.
  def initialize(staff_member:, sender:, subject: nil, body: nil, reminder: false)
    @staff_member = staff_member
    @organization = staff_member.organization
    @person = staff_member.person
    @sender = sender
    @subject_override = subject.to_s.strip.presence
    @body_override = body.to_s.strip.presence
    @reminder = reminder
  end

  def preview
    copy.merge(to_name: @person&.name, to_email: recipient_email.presence)
  end

  def call
    raise Error, "#{@staff_member.display_name} already gave you a W-9." if @staff_member.w9_received?
    if @person&.user.nil?
      raise Error, "#{@staff_member.display_name} hasn't set up their CocoScout account yet — send their onboarding invite; the W-9 is part of onboarding."
    end
    raise Error, "#{@staff_member.display_name} has no email on file — add one first." unless recipient_email.match?(URI::MailTo::EMAIL_REGEXP)

    rendered = copy
    StaffTaxFormMailer.w9_request(@staff_member, to: recipient_email, subject: rendered[:subject], body: rendered[:body]).deliver_later
    MessageService.send_direct(
      sender: @sender,
      recipient_person: @person,
      subject: rendered[:subject],
      body: rendered[:body],
      organization: @organization,
      system_generated: true
    )

    now = Time.current
    if @reminder
      @staff_member.update!(w9_last_reminded_at: now)
    else
      @staff_member.update!(w9_requested_at: now, w9_last_reminded_at: now)
    end
    @staff_member
  end

  private

  # The manager's edited copy wins; a {{first_name}} left in it (the bulk
  # draft keeps one) becomes this person's name.
  def copy
    default = default_copy
    personal = ->(text) { ContentTemplate.interpolate(text, { "first_name" => first_name }) }
    { subject: personal.call(@subject_override || default[:subject]), body: personal.call(@body_override || default[:body]) }
  end

  def default_copy
    rendered = ContentTemplateService.render(@reminder ? "staff_w9_reminder" : "staff_w9_request",
                                             self.class.shared_variables(@organization).merge(first_name: first_name))
    { subject: rendered[:subject], body: rendered[:body] }
  end

  def first_name
    @staff_member.preferred_first_name.presence ||
      @staff_member.first_name.presence ||
      @person&.first_name.presence || "there"
  end

  def recipient_email
    (@person&.email.presence || @staff_member.personal_email).to_s.strip.downcase
  end
end

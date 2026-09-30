# frozen_string_literal: true

# A manager asks staff to check and confirm their work availability: an email
# plus a parallel in-app message, both linking to their Work Availability
# page. The copy comes from the "staff_availability_confirm_request" template,
# shown to the manager as an editable draft first (one draft for a group,
# with {{first_name}} filled per person as it's sent). Sent from
# StaffAvailabilityNudgeJob, never the request thread.
class StaffAvailabilityNudger
  TEMPLATE = "staff_availability_confirm_request"

  # The draft for asking one or many: {{first_name}} left in.
  def self.draft(organization:)
    rendered = ContentTemplateService.render(TEMPLATE, shared_variables(organization))
    { subject: rendered[:subject], body: rendered[:body] }
  end

  def self.shared_variables(organization)
    {
      organization_name: organization.name,
      availability_url: Rails.application.routes.url_helpers.my_work_availability_url(**ActionMailer::Base.default_url_options)
    }
  end

  # Only someone with an account can open their availability page; everyone
  # else sets it during onboarding.
  def self.requestable?(staff_member)
    staff_member.person&.user.present? && email_for(staff_member).present?
  end

  def self.email_for(staff_member)
    (staff_member.person&.email.presence || staff_member.personal_email).to_s.strip.downcase.presence
  end

  def self.call(...)
    new(...).call
  end

  def initialize(staff_member:, sender:, subject: nil, body: nil)
    @staff_member = staff_member
    @sender = sender
    @subject = subject.to_s.strip.presence
    @body = body.to_s.strip.presence
  end

  # This person's copy, name filled in, for the single-person draft modal.
  def preview
    personalized.merge(to_name: @staff_member.display_name, to_email: self.class.email_for(@staff_member))
  end

  def call
    return false unless self.class.requestable?(@staff_member)

    copy = personalized
    StaffAvailabilityMailer.confirm_request(@staff_member, to: self.class.email_for(@staff_member),
                                                           subject: copy[:subject], body: copy[:body]).deliver_later
    MessageService.send_direct(sender: @sender, recipient_person: @staff_member.person,
                               subject: copy[:subject], body: copy[:body],
                               organization: @staff_member.organization, system_generated: true)
    true
  end

  private

  def personalized
    draft = self.class.draft(organization: @staff_member.organization)
    fill = ->(text) { ContentTemplate.interpolate(text, { "first_name" => first_name }) }
    { subject: fill.call(@subject || draft[:subject]), body: fill.call(@body || draft[:body]) }
  end

  def first_name
    @staff_member.preferred_first_name.presence || @staff_member.first_name.presence ||
      @staff_member.person&.first_name.presence || "there"
  end
end

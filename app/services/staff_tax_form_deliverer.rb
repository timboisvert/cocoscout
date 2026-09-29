# frozen_string_literal: true

# Delivers a recipient copy of a 1099-NEC: an email that points them at their
# secure copy in My Payments, and a parallel in-app message. Copy comes from
# the "staff_1099_ready" content template. The PDF itself is generated on
# demand at the recipient page rather than attached to the email so the file
# never sits in an inbox unencrypted.
class StaffTaxFormDeliverer
  include Rails.application.routes.url_helpers

  def self.call(...)
    new(...).call
  end

  def initialize(form:, sender:)
    @form = form
    @sender = sender
    @person = form.person
    @organization = form.organization
  end

  def call
    email = recipient_email
    return if email.blank?

    rendered = ContentTemplateService.render("staff_1099_ready", {
      first_name: @person.first_name.presence || @person.name.to_s.split(" ").first || "there",
      organization_name: @organization.name,
      tax_year: @form.tax_year,
      form_1099_url: my_form_1099_url(@organization.id, @form.tax_year, **ActionMailer::Base.default_url_options)
    })

    StaffTaxFormMailer.form_1099_ready(@form, to: email, subject: rendered[:subject], body: rendered[:body]).deliver_later
    MessageService.send_direct(
      sender: @sender,
      recipient_person: @person,
      subject: rendered[:subject],
      body: rendered[:body],
      organization: @organization,
      system_generated: true
    )
  end

  private

  def recipient_email
    (@person.email.presence || @person.user&.email_address).to_s.strip.downcase
  end
end

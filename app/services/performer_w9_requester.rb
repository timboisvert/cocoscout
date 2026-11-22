# frozen_string_literal: true

# Requests a Form W-9 from someone an organization pays who isn't on its staff
# (a performer, a contract person paid personally, an instructor), once it has
# paid them REQUEST_AT_CENTS in the year, a little before the 1099 amount so
# the W-9 is in hand by then (Tim, 2026-11-22). An email and a notification,
# both pointing at their page about the year; the words come from
# PerformerTaxTemplates. Records it on their W9Request.
class PerformerW9Requester
  include Rails.application.routes.url_helpers

  REQUEST_AT_CENTS = 1_500_00

  def self.call(...) = new(...).call

  # They can fill a W-9 in only behind a sign-in, so only people with an
  # account and an email are requested.
  def self.requestable?(person)
    person.user.present? && person.email.to_s.match?(URI::MailTo::EMAIL_REGEXP)
  end

  def initialize(organization:, person:, paid_cents:, tax_year:, reminder: false, now: Time.current)
    @organization = organization
    @person = person
    @paid_cents = paid_cents
    @tax_year = tax_year
    @reminder = reminder
    @now = now
  end

  def call
    key = @reminder ? "performer_w9_reminder" : "performer_w9_request"
    rendered = ContentTemplateService.render(key, variables)
    StaffTaxFormMailer.performer_w9_request(to: @person.email.to_s.strip.downcase, subject: rendered[:subject], body: rendered[:body]).deliver_later
    MessageService.send_direct(
      template_key: key, push_body: rendered[:push_body], sender: nil, recipient_person: @person,
      subject: rendered[:subject], body: rendered[:body], organization: @organization, system_generated: true
    )

    request = W9Request.find_or_initialize_by(organization: @organization, person: @person)
    if request.new_record?
      request.update!(requested_at: @now)
    else
      request.update!(last_reminded_at: @now)
    end
    request
  end

  private

  def variables
    {
      first_name: @person.first_name.presence || "there",
      organization_name: @organization.name,
      paid_words: money(@paid_cents),
      threshold_words: money(TaxForm1099.threshold_cents(@tax_year)),
      tax_year: @tax_year.to_s,
      overview_url: my_tax_year_url(@organization.id, **ActionMailer::Base.default_url_options)
    }
  end

  def money(cents) = ActiveSupport::NumberHelper.number_to_currency(cents / 100.0, precision: 0)
end

# frozen_string_literal: true

# Reminding the people a show owes who haven't set up how they're paid. Who
# they are and what each is owed here (their unpaid payout lines plus unpaid
# advances for the show), the one draft (payout_setup_reminder with
# {{recipient_name}} and {{amount}} left in, filled per person when sent),
# and sending the manager's edited copy to the people they kept ticked.
# Nothing sends without that draft being seen first.
class PayoutSetupReminders
  TEMPLATE = "payout_setup_reminder"

  Recipient = Data.define(:person, :amount_cents) do
    # Reminders arrive as CocoScout messages, so they need a login.
    def reachable? = person.user.present?
    def email = person.user&.email_address.presence || person.email
    def first_name = person.name.to_s.split(/\s+/).first.presence || person.name.to_s
  end

  def self.recipients(show_payout)
    show = show_payout.show
    owed = Hash.new(0)

    show_payout.line_items.not_already_paid.includes(:payee).each do |item|
      payee = item.payee
      next unless payee.is_a?(Person) && !payee.can_receive_payouts?

      owed[payee] += (item.amount.to_d * 100).round
    end

    show.production.person_advances.for_show(show).unpaid.includes(:person).each do |advance|
      person = advance.person
      next if person.nil? || person.can_receive_payouts?

      owed[person] += (advance.original_amount.to_d * 100).round
    end

    owed.select { |_, cents| cents.positive? }
        .map { |person, cents| Recipient.new(person: person, amount_cents: cents) }
        .sort_by { |recipient| recipient.person.name.to_s.downcase }
  end

  def self.draft(organization)
    rendered = ContentTemplateService.render(TEMPLATE, shared_variables(organization))
    { subject: rendered[:subject], body: rendered[:body] }
  end

  # Returns how many were sent: the ticked recipients who can be reached.
  def self.send!(organization:, recipients:, subject:, body:)
    recipients.select(&:reachable?).each do |recipient|
      variables = shared_variables(organization).merge(
        "recipient_name" => recipient.first_name,
        "amount" => ActiveSupport::NumberHelper.number_to_currency(recipient.amount_cents / 100.0)
      )
      ContentTemplateService.deliver(
        template_key: TEMPLATE, variables: variables, sender: nil, recipients: [ recipient.person ],
        organization: organization, message_type: :system, visibility: :personal,
        subject_override: ContentTemplate.interpolate(subject, variables),
        body_override: ContentTemplate.interpolate(body, variables)
      )
    end.size
  end

  def self.shared_variables(organization)
    { "organization_name" => organization.name,
      "setup_link" => Rails.application.routes.url_helpers.my_payments_setup_url(**ActionMailer::Base.default_url_options) }
  end
end

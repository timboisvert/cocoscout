# frozen_string_literal: true

# A yearly Pro plan is about to renew (Tim, 2026-11-24): 30 days before, the
# organization's billing contacts hear the day, what will be charged, and
# where to change the payment method or cancel. CocoScout's own email, since
# Stripe's renewal emails are switched off. Once for each renewal.
#
# Only a yearly plan that will renew: a monthly plan gets a bill every month
# anyway, a canceled plan doesn't renew, and a trial ending isn't a renewal.
class ProRenewalReminder
  BEFORE = 30.days

  def self.due(now: Time.current)
    Organization.where(subscription_interval: "year", subscription_status: "active", subscription_canceled_at: nil)
                .where.not(stripe_subscription_id: nil)
                .where(subscription_current_period_end: now..(now + BEFORE))
                .where("renewal_reminded_for IS NULL OR renewal_reminded_for < subscription_current_period_end - interval '1 day'")
  end

  attr_reader :organization

  def initialize(organization)
    @organization = organization
  end

  # Sends the reminder and remembers the renewal it was for. Returns the
  # addresses it went to; none when Stripe has no renewal coming (the amount
  # is Stripe's own, so a discount or a credit is counted) or nobody to email.
  def send!
    amount_cents = renewal_amount_cents
    contacts = organization.billing_contacts
    return [] if amount_cents.nil? || contacts.empty?

    contacts.each do |contact|
      AppMailer.with(template_key: "cocoscout_pro_renewal", to: contact.email, variables: email_variables(contact.first_name, amount_cents)).send_template.deliver_now
    end
    organization.update_column(:renewal_reminded_for, organization.subscription_current_period_end)
    contacts.map(&:email)
  end

  def email_variables(first_name, amount_cents)
    url_options = Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
    {
      "first_name" => first_name.presence || "there",
      "organization_name" => organization.name,
      "renews_on" => organization.subscription_current_period_end.in_time_zone(organization.time_zone.presence || Time.zone.name).strftime("%B %-d, %Y"),
      "charge_line" => charge_line(amount_cents),
      "billing_url" => Rails.application.routes.url_helpers.section_manage_organization_url(organization, section: "billing", **url_options)
    }
  end

  private

  def charge_line(amount_cents)
    if amount_cents.positive?
      "#{ActiveSupport::NumberHelper.number_to_currency(amount_cents / 100.0)} will be charged to the payment method on file with CocoScout that day."
    else
      "Nothing will be charged that day: the credit on your CocoScout bills covers it."
    end
  end

  # What Stripe will charge at the renewal. nil when Stripe has no renewal
  # coming or can't be reached: the reminder waits for tomorrow's run.
  def renewal_amount_cents
    preview = Stripe::Invoice.create_preview({ customer: organization.stripe_customer_id, subscription: organization.stripe_subscription_id })
    preview.to_hash[:amount_due]&.to_i
  rescue Stripe::StripeError => e
    Rails.logger.warn("[ProRenewalReminder] no renewal preview for organization #{organization.id}: #{e.message}")
    nil
  end
end

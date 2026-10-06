# frozen_string_literal: true

# Keeps the Stripe customer's email on the organization's first billing
# contact, so the failed-payment and expiring-card emails Stripe itself still
# sends reach the right person. Best effort: a Stripe error is logged.
class BillingContactsStripeSyncJob < ApplicationJob
  queue_as :default

  def perform(organization_id)
    organization = Organization.find_by(id: organization_id)
    return if organization&.stripe_customer_id.blank?

    contact = organization.billing_contacts.first
    return unless contact

    Stripe::Customer.update(organization.stripe_customer_id, { email: contact.email, name: organization.name })
  rescue Stripe::StripeError => e
    Rails.logger.error "Billing contact sync to Stripe failed for organization #{organization_id}: #{e.message}"
  end
end

# frozen_string_literal: true

# Translates a Stripe Subscription into an Organization's subscription columns.
# Used by both the Stripe webhook and the checkout success page (idempotent
# dual-write, mirroring the course-registration pattern). #on_paid_plan? on the
# organization reads the columns this service writes.
class SubscriptionSyncService
  # Stripe subscription statuses that grant Pro access.
  ACCESS_STATUSES = %w[active trialing past_due].freeze

  def initialize(organization, stripe_subscription)
    @organization = organization
    @subscription = stripe_subscription
  end

  # Convenience: fetch the subscription from Stripe by id, then sync.
  def self.from_id(organization, subscription_id)
    new(organization, Stripe::Subscription.retrieve(subscription_id)).call
  end

  # The org's second subscription, the monthly one that carries the metered
  # usage prices (StaffMeterService#ensure_staffing_subscription!). Its events
  # say nothing about Pro: an active usage subscription must never make an org
  # Pro, and its id must never replace the Pro subscription's.
  def self.usage_subscription?(organization, subscription)
    metadata = subscription.respond_to?(:metadata) ? subscription.metadata : nil
    kind = metadata.respond_to?(:[]) ? metadata["kind"] : nil
    kind == "staffing" || (subscription.id.present? && subscription.id == organization.staffing_subscription_id)
  end

  def call
    if self.class.usage_subscription?(@organization, @subscription)
      # Stripe ended it (or someone did, in the dashboard): forget it, so the
      # next metered month makes a fresh one.
      if @subscription.status == "canceled" && @organization.staffing_subscription_id == @subscription.id
        @organization.update_column(:staffing_subscription_id, nil)
      end
      return @organization
    end

    status = @subscription.status
    item = @subscription.items&.data&.first

    @organization.update!(
      stripe_subscription_id: @subscription.id,
      stripe_customer_id: @subscription.customer,
      subscription_status: status,
      subscription_interval: item&.price&.recurring&.interval,
      subscription_current_period_end: unix_to_time(period_end(item)),
      subscription_canceled_at: unix_to_time(@subscription["canceled_at"]),
      subscription_tier: status.in?(ACCESS_STATUSES) ? "paid" : "free"
    )
    # Pro ended: usage stops billing with it.
    UsageSubscriptionSyncJob.perform_later(@organization.id) if @organization.staffing_subscription_id.present? && !@organization.bills_usage?
    @organization
  end

  private

  # current_period_end lives on the subscription in older Stripe API versions and
  # on the subscription item in newer ones — read whichever is present.
  def period_end(item)
    @subscription["current_period_end"] || item&.[]("current_period_end")
  end

  def unix_to_time(timestamp)
    timestamp.present? ? Time.zone.at(timestamp) : nil
  end
end

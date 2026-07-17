# frozen_string_literal: true

# Fair-pricing billing for the money/production-economics module: an org is
# charged $3/month per *active* performer — active meaning paid through a payout
# run that calendar month (a durable PerformerActivation, recorded when we pay
# them). This lines up with the month Stripe bills us the ~$2 active-account fee.
# A performer you don't pay that month costs nothing, and paying someone any
# number of times in a month is a single $3 — no per-payment fee.
#
# The monthly meter job reports the active count as usage on the org's metered
# Stripe subscription item; #monthly_estimate_cents drives the running preview
# shown in Billing & Plan.
class PerformerBillingService
  PER_ACTIVE_PERFORMER_CENTS = 300

  def initialize(organization, month: Date.current)
    @organization = organization
    @month = month.to_date.beginning_of_month
  end

  def activations
    @organization.performer_activations.for_month(@month)
  end

  def active_count
    activations.count
  end

  # The people billable this month (paid through a payout run this month).
  def active_performers
    Person.where(id: activations.select(:person_id)).order(:name)
  end

  def active_performer_cents
    active_count * PER_ACTIVE_PERFORMER_CENTS
  end

  def monthly_estimate_cents
    active_performer_cents
  end
end

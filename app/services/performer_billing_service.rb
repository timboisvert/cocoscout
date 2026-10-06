# frozen_string_literal: true

# Fair-pricing billing for the money/production-economics module: an org is
# charged $3/month per *active* performer — active meaning they performed that
# calendar month in a show that pays them, and the show is over (a durable
# PerformerActivation, recorded by UsageSweepJob; see UsageRules). A performer
# with no paid show that month costs nothing, and any number of paid shows in
# a month is a single $3.
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

  # The people billable this month (a paid show this month that's over).
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

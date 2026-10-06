# frozen_string_literal: true

# Fair-pricing billing for the staffing module: an org is charged $5/month per
# *active* staff member — active meaning paid staff pay through a payout run
# that calendar month. A staffer who isn't paid that month (an unpaid role, a
# volunteer, someone only scheduled) costs nothing, and paying someone any
# number of times in a month is a single $5.
#
# The monthly meter job reports the active count as usage on the org's metered
# Stripe subscription item; #monthly_estimate_cents drives the running preview
# shown in the staffing hub and Billing & Plan.
class StaffBillingService
  PER_ACTIVE_STAFF_CENTS = 500

  def initialize(organization, month: Date.current)
    @organization = organization
    @month = month.to_date.beginning_of_month
  end

  # Staff members billable this month — those paid staff pay through a payout
  # run (a durable StaffActivation, recorded when we pay them).
  # Billing follows activations, not the roster — someone paid this month is
  # billable even if they were marked inactive afterwards, so no .active
  # filter here (else the count and the name list drift apart).
  def active_staff_members
    person_ids = activations.select(:person_id)
    @organization.organization_staff_members.where(person_id: person_ids)
  end

  def activations
    @organization.staff_activations.for_month(@month)
  end

  def active_count
    activations.count
  end

  def active_staff_cents
    active_count * PER_ACTIVE_STAFF_CENTS
  end

  def monthly_estimate_cents
    active_staff_cents
  end
end

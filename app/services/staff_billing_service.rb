# frozen_string_literal: true

# Fair-pricing billing for the staffing module: an org is charged $5/month per
# *active* staff member — active meaning scheduled for at least one shift that
# calendar month. A staffer who doesn't work that month costs nothing. On top of
# that, the $1 per-extra-payment fees collected during pay runs are billed too.
#
# The monthly meter job reports the active count as usage on the org's metered
# Stripe subscription item; #monthly_estimate_cents drives the running preview
# shown in the staffing hub and Billing & Plan.
class StaffBillingService
  PER_ACTIVE_STAFF_CENTS = 500

  def initialize(organization, month: Date.current)
    @organization = organization
    @range = month.beginning_of_month.beginning_of_day..month.end_of_month.end_of_day
  end

  # Staff members scheduled for >= 1 shift this month (their person is assigned
  # to an org shift starting within the month).
  def active_staff_members
    scheduled_ids = ShiftAssignment.joins(:shift)
                                   .where(shifts: { organization_id: @organization.id, starts_at: @range })
                                   .distinct.pluck(:person_id)
    @organization.organization_staff_members.active.where(person_id: scheduled_ids)
  end

  def active_count
    active_staff_members.count
  end

  def active_staff_cents
    active_count * PER_ACTIVE_STAFF_CENTS
  end

  # $1 extra-payment fees charged across this month's pay runs.
  def extra_payment_fee_cents
    @organization.payout_batches.where(created_at: @range).sum(:extra_payment_fee_cents)
  end

  def monthly_estimate_cents
    active_staff_cents + extra_payment_fee_cents
  end

  # Report this month's active-staff usage to Stripe so it's billed on the org's
  # existing subscription. No-op until a metered staffing subscription item is
  # configured on the org (kept safe so nothing charges by accident before the
  # Stripe price is wired up).
  def report_usage!
    item_id = @organization.try(:staff_meter_subscription_item_id)
    return :not_configured if item_id.blank?

    Stripe::SubscriptionItem.create_usage_record(
      item_id,
      quantity: active_count,
      timestamp: Time.current.to_i,
      action: "set"
    )
    :reported
  end
end

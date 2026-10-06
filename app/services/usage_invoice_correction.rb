# frozen_string_literal: true

# Makes each usage bill equal what CocoScout says the org owes: $5 for every
# staff member and $3 for every performer it paid through Stripe in the month
# the bill covers (StaffActivation / PerformerActivation). Stripe's meter does
# the counting, but what it has counted can't be taken back (the meter took
# October 2026's scheduled-but-unpaid staff before the rule was fixed), and a
# usage period that doesn't start on the 1st straddles two months. So when
# Stripe drafts a usage bill (invoice.created, and Stripe holds the bill until
# our webhook answers), the difference goes on it as one correction line.
class UsageInvoiceCorrection
  PREFIX = "Correction:"

  def self.apply!(record)
    return unless record&.kind == "usage" && record.status == "draft"

    organization = record.organization
    month = billed_month(record)
    return if month.nil? || organization.stripe_customer_id.blank?

    staff = StaffActivation.where(organization: organization).for_month(month).count
    performers = PerformerActivation.where(organization: organization).for_month(month).count
    expected = staff * StaffBillingService::PER_ACTIVE_STAFF_CENTS + performers * PerformerBillingService::PER_ACTIVE_PERFORMER_CENTS
    on_bill = record.lines.sum { |line| line["amount_cents"].to_i }
    difference = expected - on_bill
    return if difference.zero?

    Stripe::InvoiceItem.create(
      { customer: organization.stripe_customer_id, invoice: record.stripe_invoice_id, amount: difference, currency: "usd",
        description: "#{PREFIX} #{staff} staff and #{performers} performers paid through CocoScout in #{month.strftime('%B %Y')}",
        metadata: { kind: "usage_correction", organization_id: organization.id, month: month.iso8601 } },
      { idempotency_key: "usage-correction-#{record.stripe_invoice_id}-#{difference}" }
    )
  end

  # The month a bill mostly covers: the middle of its period. (A usage period
  # starting on the 30th is that next month; one starting on the 1st is that
  # month.)
  def self.billed_month(record)
    return nil unless record.period_start && record.period_end

    middle = record.period_start + ((record.period_end - record.period_start) / 2)
    middle.in_time_zone.to_date.beginning_of_month
  end
end

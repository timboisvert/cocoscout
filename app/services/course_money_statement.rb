# frozen_string_literal: true

# A course's full money picture in one place: every payment in, refund out, fee
# taken, and payout sent — each tied to the Stripe object behind it, so a course
# is traceable end to end without leaving CocoScout. Read-only presenter over
# existing records (registrations + the course payout run).
class CourseMoneyStatement
  Payment = Struct.new(:name, :amount_cents, :fee_cents, :at, :stripe_payment_intent_id, keyword_init: true)
  Refund  = Struct.new(:name, :amount_cents, :at, :stripe_refund_id, keyword_init: true)
  Payout  = Struct.new(:name, :amount_cents, :status, :stripe_transfer_id, :kind, keyword_init: true)

  def initialize(course_offering)
    @course_offering = course_offering
  end

  def payments
    confirmed_registrations.map do |r|
      Payment.new(
        name: r.person&.name || "Registration ##{r.id}",
        amount_cents: r.amount_cents.to_i,
        fee_cents: r.cocoscout_fee_cents.to_i,
        at: r.registered_at || r.created_at,
        stripe_payment_intent_id: r.stripe_payment_intent_id
      )
    end
  end

  def refunds
    refunded_registrations.map do |r|
      Refund.new(
        name: r.person&.name || "Registration ##{r.id}",
        amount_cents: r.amount_cents.to_i,
        at: r.refunded_at,
        stripe_refund_id: r.stripe_refund_id
      )
    end
  end

  def payouts
    payout_contributions.map do |c|
      item = c.payout_batch_item
      Payout.new(
        name: payee_name(c),
        amount_cents: item&.amount_cents.to_i,
        status: payout_status(item),
        stripe_transfer_id: item&.stripe_transfer_id,
        kind: c.payee.is_a?(Organization) ? "Organization's share" : (c.label || "Payout")
      )
    end
  end

  # Gross → refunds → revenue → fee → net → paid out → org kept, all in cents.
  def totals
    gross = confirmed_registrations.sum { |r| r.amount_cents.to_i } +
      refunded_registrations.sum { |r| r.amount_cents.to_i }
    refunded = refunded_registrations.sum { |r| r.amount_cents.to_i }
    fees = confirmed_registrations.sum { |r| r.cocoscout_fee_cents.to_i }
    revenue = gross - refunded
    paid_out = payout_contributions.sum { |c| c.payout_batch_item&.amount_cents.to_i }

    {
      gross_cents: gross,
      refunds_cents: refunded,
      revenue_cents: revenue,
      fees_cents: fees,
      net_cents: revenue - fees,
      paid_out_cents: paid_out
    }
  end

  private

  def confirmed_registrations
    @confirmed_registrations ||= @course_offering.course_registrations.confirmed.includes(:person).to_a
  end

  def refunded_registrations
    @refunded_registrations ||= @course_offering.course_registrations.refunded.includes(:person).to_a
  end

  def payout_contributions
    @payout_contributions ||= begin
      payout = @course_offering.course_offering_payout
      if payout
        sources = [ payout ] + payout.line_items.to_a
        PayoutContribution.where(source: sources).includes(:payout_batch_item, :payee).to_a
      else
        []
      end
    end
  end

  def payee_name(contribution)
    payee = contribution.payee
    return "#{payee.name} (your organization)" if payee.is_a?(Organization)

    payee.try(:name) || contribution.label || "Payout"
  end

  def payout_status(item)
    return "unpaid" if item.nil?
    return "paid" if item.paid?
    return "failed" if item.error.present?

    "awaiting payout"
  end
end

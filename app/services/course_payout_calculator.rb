# frozen_string_literal: true

# Calculates what the organization owes a contractor for a course offering.
#
# Revenue flow:
#   Student pays via Stripe → fees are determined by promo code coverage:
#     - No promo:         CocoScout keeps 5% platform fee, org gets 95%
#     - coverage "full":  All fees waived, org gets 100%
#     - "platform_only":  Only Stripe processing fees deducted, no CocoScout fee
#
# This calculator computes what the org owes the contractor from
# their share of the net revenue (after applicable fees).
#
# No contract = no payout needed (org already has all the money).
class CoursePayoutCalculator
  PLATFORM_FEE_PERCENTAGE = 5.0

  attr_reader :course_offering

  def initialize(course_offering)
    @course_offering = course_offering
  end

  def calculate!
    payout = course_offering.course_offering_payout ||
      course_offering.build_course_offering_payout

    result = compute

    payout.assign_attributes(
      total_revenue_cents: result[:total_revenue_cents],
      platform_fee_cents: result[:platform_fee_cents],
      net_revenue_cents: result[:net_revenue_cents],
      total_payout_cents: result[:total_payout_cents],
      status: "calculated",
      calculated_at: Time.current
    )

    CourseOfferingPayout.transaction do
      payout.save!
      # Only auto-generate line items when there's a contract
      if result[:line_items].any?
        payout.line_items.destroy_all
        result[:line_items].each do |li_attrs|
          payout.line_items.create!(li_attrs)
        end
      end
    end

    payout
  end

  def preview
    compute
  end

  # Revenue breakdown (usable with or without a contract)
  def revenue_summary
    total_revenue_cents = compute_total_revenue
    effective_revenue = course_offering.course_offering_payout&.total_revenue_override_cents || total_revenue_cents
    platform_fee_cents = compute_platform_fee(effective_revenue)
    net_revenue_cents = effective_revenue - platform_fee_cents

    {
      total_revenue_cents: total_revenue_cents,
      platform_fee_cents: platform_fee_cents,
      net_revenue_cents: net_revenue_cents,
      coverage_type: coverage_type
    }
  end

  private

  def compute
    total_revenue_cents = compute_total_revenue
    effective_revenue = course_offering.course_offering_payout&.total_revenue_override_cents || total_revenue_cents
    platform_fee_cents = compute_platform_fee(effective_revenue)
    net_revenue_cents = effective_revenue - platform_fee_cents

    contract = course_offering.contract
    if contract&.revenue_share?
      line_items = build_contractor_line_items(net_revenue_cents)
      total_payout_cents = line_items.sum { |li| li[:amount_cents] }
    else
      line_items = []
      total_payout_cents = 0
    end

    {
      total_revenue_cents: total_revenue_cents,
      platform_fee_cents: platform_fee_cents,
      net_revenue_cents: net_revenue_cents,
      total_payout_cents: total_payout_cents,
      line_items: line_items
    }
  end

  def compute_total_revenue
    confirmed = course_offering.course_registrations.confirmed.sum(:amount_cents)
    refunded = course_offering.course_registrations.refunded.sum(:amount_cents)
    confirmed - refunded
  end

  # Determine the platform fee based on coverage_type from any promo code
  def compute_platform_fee(effective_revenue)
    case coverage_type
    when "full"
      # Promo covers all fees — org gets 100%
      0
    when "platform_only"
      # Promo covers CocoScout fee — only actual Stripe processing fees apply
      confirmed_stripe_fees = course_offering.course_registrations.confirmed.sum(:stripe_fee_cents)
      refunded_stripe_fees = course_offering.course_registrations.refunded.sum(:stripe_fee_cents)
      confirmed_stripe_fees - refunded_stripe_fees
    else
      # Standard 5% platform fee
      (effective_revenue * PLATFORM_FEE_PERCENTAGE / 100.0).round
    end
  end

  # Look up the coverage_type from the promo code used to create this course offering
  def coverage_type
    @coverage_type ||= course_offering.feature_credit_redemption&.feature_credit&.coverage_type
  end

  def build_contractor_line_items(net_revenue_cents)
    contract = course_offering.contract
    contractor_pct = contract.contractor_share_percentage
    contractor_amount = (net_revenue_cents * contractor_pct / 100.0).round

    [ {
      payee_type: "Contractor",
      payee_id: contract.contractor_id,
      amount_cents: contractor_amount,
      label: contract.contractor_name,
      calculation_details: {
        type: "contract_revenue_share",
        contract_id: contract.id,
        share_percentage: contractor_pct,
        org_share_percentage: contract.revenue_share_percentage,
        net_revenue_cents: net_revenue_cents
      }
    } ]
  end
end

# frozen_string_literal: true

# Calculates what the organization owes a contractor for a course offering.
#
# Revenue flow:
#   Student pays via Stripe → fees are determined by promo code coverage:
#     - No promo:         CocoScout keeps the platform fee (PLATFORM_FEE_PERCENTAGE, currently 10%)
#     - coverage "full":  All fees waived, org gets 100%
#     - "platform_only":  Only Stripe processing fees deducted, no CocoScout fee
#
# This calculator computes what the org owes the contractor from
# their share of the net revenue (after applicable fees).
#
# No contract = no payout needed (org already has all the money).
class CoursePayoutCalculator
  # Canonical rate lives on CourseRegistration; aliased here for readability.
  PLATFORM_FEE_PERCENTAGE = CourseRegistration::PLATFORM_FEE_PERCENTAGE

  attr_reader :course_offering

  def initialize(course_offering)
    @course_offering = course_offering
  end

  # Keep the revenue summary (revenue / fee / net) current with registrations,
  # without regenerating line items — safe to run on every payout-page view so a
  # stale calculation doesn't linger. No-op if there's no payout or it's paid.
  def refresh_summary!
    payout = course_offering.course_offering_payout
    return if payout.nil? || payout.paid?

    result = compute
    payout.update!(
      total_revenue_cents: result[:total_revenue_cents],
      platform_fee_cents: result[:platform_fee_cents],
      net_revenue_cents: result[:net_revenue_cents]
    )
    payout
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
      line_items = build_revenue_share_line_items(net_revenue_cents)
      total_payout_cents = line_items.sum { |li| li[:amount_cents] }
    elsif contract&.ticket_revenue_minus_fee?
      line_items = build_flat_fee_line_items(net_revenue_cents)
      total_payout_cents = line_items.sum { |li| li[:amount_cents] }
    else
      # No revenue contract — pay instructors per their standalone per-run split.
      line_items = build_standalone_instructor_line_items(net_revenue_cents)
      total_payout_cents = line_items.sum { |li| li[:amount_cents] }
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
    # Refunded registrations already leave the `confirmed` scope, so the money we
    # actually kept is just the confirmed sum — don't subtract refunds again.
    course_offering.course_registrations.confirmed.sum(:amount_cents)
  end

  # Determine the platform fee based on coverage_type from any promo code
  def compute_platform_fee(_effective_revenue)
    case coverage_type
    when "full"
      # Promo covers all fees — org gets 100%
      0
    when "platform_only"
      # Promo covers the CocoScout fee — only actual processing fees apply.
      course_offering.course_registrations.confirmed.sum(:stripe_fee_cents)
    else
      # The CocoScout fee ACTUALLY charged on these registrations (stored per
      # registration), not a re-computed rate — so it reflects what was really
      # taken, even as the rate changes over time.
      course_offering.course_registrations.confirmed.sum(:cocoscout_fee_cents)
    end
  end

  # Look up the coverage_type from the promo code used to create this course offering
  def coverage_type
    @coverage_type ||= course_offering.feature_credit_redemption&.feature_credit&.coverage_type
  end

  def build_revenue_share_line_items(net_revenue_cents)
    contract = course_offering.contract
    contractor_pct = contract.contractor_share_percentage
    contractor_amount = (net_revenue_cents * contractor_pct / 100.0).round

    [ {
      # Pay the contractor's linked Person — the identity that holds the Stripe
      # Connect account and ledger (a Contractor record has no stripe_account_id).
      payee_type: "Person",
      payee_id: contract.contractor&.person_id,
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

  # Standalone (no-contract) course: each instructor with a configured split gets
  # a line item paid to their Person (holds the Stripe account).
  def build_standalone_instructor_line_items(net_revenue_cents)
    course_offering.course_offering_instructors.filter_map do |coi|
      amount = coi.payout_amount_cents(net_revenue_cents)
      next if amount <= 0 || coi.person_id.nil?

      {
        payee_type: "Person",
        payee_id: coi.person_id,
        amount_cents: amount,
        label: coi.person.name,
        calculation_details: {
          type: "instructor",
          instructor_person_id: coi.person_id,
          payout_type: coi.payout_type,
          net_revenue_cents: net_revenue_cents
        }
      }
    end
  end

  def build_flat_fee_line_items(net_revenue_cents)
    contract = course_offering.contract
    fee_cents = (contract.flat_fee_amount * 100).round
    contractor_amount = [ net_revenue_cents - fee_cents, 0 ].max

    [ {
      # Pay the contractor's linked Person (holds the Stripe account + ledger).
      payee_type: "Person",
      payee_id: contract.contractor&.person_id,
      amount_cents: contractor_amount,
      label: contract.contractor_name,
      calculation_details: {
        type: "contract_flat_fee",
        contract_id: contract.id,
        flat_fee_cents: fee_cents,
        org_keeps_cents: [ fee_cents, net_revenue_cents ].min,
        net_revenue_cents: net_revenue_cents
      }
    } ]
  end
end

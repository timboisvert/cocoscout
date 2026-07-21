# frozen_string_literal: true

# The final settlement for a course payout: who gets paid, how much, and where
# each payment comes from. One source of truth used by both the payout page
# (display) and CoursePayoutRunService (run assembly) so the numbers always agree.
#
# The CocoScout platform fee comes off the top (net revenue). Then:
#
#   * WITH a contract: the contractor gets their contractual share of net (e.g.
#     50% after fees), automatically. Anything paid to an instructor comes out of
#     the CONTRACTOR's half — the org's contractual share is fixed. The org keeps
#     net − contractor_share.  (Scenario 1)
#
#   * WITHOUT a contract: the org keeps everything after fees, minus whatever it
#     chooses to pay an instructor. Instructor pay comes out of the ORG's share.
#     Paying an instructor $0 (or not at all) just means the org keeps it all.
#     (Scenarios 2 & 3)
class CoursePayoutSettlement
  def initialize(payout)
    @payout = payout
    @organization = payout.course_offering.production.organization
  end

  # [{ payee:, name:, amount_cents:, kind:, source:, is_org: }], positive amounts
  # only, org row last.
  def rows
    @rows ||= build_rows
  end

  # What the organization takes home after everyone else is paid.
  def org_keeps_cents
    contract? ? (net_cents - contract_total) : (net_cents - non_contract_total)
  end

  private

  def build_rows
    result = []

    if contract?
      # Instructor (and any other manual) payments come out of the contractor's
      # half; distribute the deduction across the contract line(s).
      remaining = non_contract_total
      contract_lines.each do |li|
        deduct = [ li.amount_cents.to_i, remaining ].min
        remaining -= deduct
        result << line_row(li, li.amount_cents.to_i - deduct)
      end
    end

    non_contract_lines.each { |li| result << line_row(li, li.amount_cents.to_i) }

    result << org_row(org_keeps_cents)
    result.select { |r| r[:amount_cents].positive? }
  end

  def line_row(line_item, amount_cents)
    { payee: line_item.payee, name: line_item.payee_name, amount_cents: amount_cents,
      kind: kind_for(line_item), source: line_item }
  end

  def org_row(amount_cents)
    { payee: @organization, name: @organization.name, amount_cents: amount_cents,
      kind: "Your organization's share", source: @payout, is_org: true }
  end

  def kind_for(line_item)
    case line_item.calculation_details["type"]
    when "contract_revenue_share" then "Contract · #{line_item.calculation_details['share_percentage'].to_i}% share"
    when "contract_flat_fee" then "Contract"
    when "instructor" then "Instructor"
    else "Payment"
    end
  end

  def line_items
    @line_items ||= @payout.line_items.to_a
  end

  def contract_lines
    @contract_lines ||= line_items.select { |li| li.calculation_details["type"].to_s.start_with?("contract_") }
  end

  def non_contract_lines
    @non_contract_lines ||= line_items - contract_lines
  end

  def contract_total
    @contract_total ||= contract_lines.sum { |li| li.amount_cents.to_i }
  end

  def non_contract_total
    @non_contract_total ||= non_contract_lines.sum { |li| li.amount_cents.to_i }
  end

  def contract?
    contract_lines.any?
  end

  def net_cents
    @payout.net_revenue_cents.to_i
  end
end

# frozen_string_literal: true

# One-off backfill for the revenue-share direction bug.
#
# When WE sell the tickets (who_sells_tickets == "org", so we hold all the ticket
# money), a revenue share should settle as us paying THEM their share — direction
# "outgoing", "Y% to them". The old wizard JS hardcoded every revenue-share row as
# "incoming / X% to us" regardless of who sold, so we-sell deals read backwards.
#
# This fixes the already-saved data: the generated rows in draft_data["payments"]
# (what the deal-terms/review render from) and any still-pending materialized
# contract_payments on active contracts. Contractor-sells deals were already
# correct and are left untouched; hand-added payments are never touched. Idempotent
# — re-running does nothing once a contract is fixed.
class RevenueShareDirectionBackfill
  Result = Struct.new(:contracts_fixed, :draft_rows_fixed, :payment_rows_fixed, keyword_init: true)

  # Matches the old "…— 50% to us" suffix the JS produced (em dash or hyphen prefix
  # is left as-is; only the "N% to us" tail is rewritten).
  SETTLEMENT_SUFFIX = /\d+%\s*to us\s*\z/i

  def self.run(dry_run: false)
    new(dry_run: dry_run).run
  end

  def initialize(dry_run: false)
    @dry_run = dry_run
    @contracts_fixed = 0
    @draft_rows_fixed = 0
    @payment_rows_fixed = 0
  end

  def run
    Contract.find_each do |contract|
      next unless we_sell_revenue_share?(contract)

      their_share = 100 - our_share(contract)
      touched = fix_draft_payments(contract, their_share)
      touched = fix_contract_payments(contract, their_share) || touched
      @contracts_fixed += 1 if touched
    end

    Result.new(contracts_fixed: @contracts_fixed, draft_rows_fixed: @draft_rows_fixed, payment_rows_fixed: @payment_rows_fixed)
  end

  private

  # Only deals where "We do" was explicitly chosen — those are the ones the JS got
  # backwards. Legacy revenue shares (no who_sells recorded) settled as "they pay
  # us", which is correct, so leave them alone.
  def we_sell_revenue_share?(contract)
    contract.draft_payment_structure == "revenue_share" &&
      contract.draft_payment_config["who_sells_tickets"] == "org"
  end

  def our_share(contract)
    (contract.draft_payment_config["revenue_our_share"].presence || 50).to_i
  end

  def settlement_row?(payment)
    payment["source"] == "Revenue share" ||
      (truthy?(payment["amount_tbd"]) && payment["description"].to_s.match?(SETTLEMENT_SUFFIX))
  end

  def guarantee_row?(payment)
    payment["source"] == "Minimum guarantee" || payment["description"] == "Minimum guarantee"
  end

  def truthy?(value)
    value == true || value == "true"
  end

  def fix_draft_payments(contract, their_share)
    payments = contract.draft_payments
    return false if payments.blank?

    changed = false
    updated = payments.map do |payment|
      next payment unless payment["direction"] == "incoming"
      next payment unless settlement_row?(payment) || guarantee_row?(payment)

      changed = true
      @draft_rows_fixed += 1
      payment.merge(
        "direction" => "outgoing",
        "description" => relabel(payment["description"], their_share)
      )
    end

    return false unless changed

    contract.update_column(:draft_data, contract.draft_data.merge("payments" => updated)) unless @dry_run
    true
  end

  # Active contracts materialized the same rows into contract_payments (no `source`
  # column there, so match on the TBD/"% to us" shape). Only pending rows — never
  # touch anything already settled.
  def fix_contract_payments(contract, their_share)
    touched = false
    contract.contract_payments.status_pending.where(direction: "incoming").find_each do |cp|
      is_settlement = cp.amount_tbd? && cp.description.to_s.match?(SETTLEMENT_SUFFIX)
      is_guarantee = cp.description.to_s == "Minimum guarantee"
      next unless is_settlement || is_guarantee

      touched = true
      @payment_rows_fixed += 1
      cp.update_columns(direction: "outgoing", description: relabel(cp.description, their_share)) unless @dry_run
    end
    touched
  end

  def relabel(description, their_share)
    return description unless description.is_a?(String)

    description.sub(SETTLEMENT_SUFFIX, "#{their_share}% to them")
  end
end

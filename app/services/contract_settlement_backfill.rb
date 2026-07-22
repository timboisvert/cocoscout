# frozen_string_literal: true

# Backfills the v2 payment dimensions (settlement_basis + who_sells_tickets) into
# existing contracts' draft_payment_config, so old contracts render and settle
# under the new logic explicitly rather than only via the legacy fallback.
#
# - Idempotent: contracts that already carry settlement_basis are skipped.
# - Non-destructive: existing ContractPayment records are never modified.
# - Reconciled: for revenue-share contracts, who-sells is inferred from the ACTUAL
#   direction of existing payments (outgoing → we sell/pay them; incoming → they
#   sell/pay us) rather than assumed, and any contract whose derived direction
#   disagrees with its existing payments is reported for review (not changed).
class ContractSettlementBackfill
  Result = Struct.new(:migrated, :skipped, :mismatches, keyword_init: true)

  class << self
    def run(dry_run: false)
      migrated = 0
      skipped = 0
      mismatches = []

      Contract.find_each do |contract|
        config = contract.draft_payment_config
        if config["settlement_basis"].present?
          skipped += 1
          next
        end

        basis = derive_basis(contract)
        who_sells = derive_who_sells(contract, basis)

        existing = contract.contract_payments.distinct.pluck(:direction).compact
        derived = direction_for(who_sells, config)
        if existing.any? && existing.any? { |d| d != derived }
          mismatches << { contract_id: contract.id, derived: derived, existing: existing }
        end

        unless dry_run
          new_config = config.merge("settlement_basis" => basis)
          new_config["who_sells_tickets"] = who_sells if who_sells
          contract.update_draft_step(:payment_config, new_config)
        end
        migrated += 1
      end

      Result.new(migrated: migrated, skipped: skipped, mismatches: mismatches)
    end

    def derive_basis(contract)
      case contract.draft_payment_structure
      when "revenue_share" then "revenue_share"
      when "flat_fee"
        contract.draft_payment_config["flat_fee_direction"] == "ticket_revenue_minus_fee" ? "revenue_minus_fee" : "flat"
      else "flat"
      end
    end

    def derive_who_sells(contract, basis)
      return "org" if basis == "revenue_minus_fee"
      return nil unless basis == "revenue_share"

      # Reconcile from reality: existing payment direction tells us who sold.
      dirs = contract.contract_payments.distinct.pluck(:direction).compact
      return "org" if dirs == [ "outgoing" ]
      return "contractor" if dirs == [ "incoming" ]

      "contractor" # legacy default when there's nothing to reconcile against
    end

    def direction_for(who_sells, config)
      case who_sells
      when "org" then "outgoing"
      when "contractor" then "incoming"
      else
        dir = config["flat_fee_direction"]
        dir.in?(%w[incoming outgoing]) ? dir : "incoming"
      end
    end
  end
end

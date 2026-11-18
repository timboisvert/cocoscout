# frozen_string_literal: true

# A weekly, monthly or whole-run settlement covers every show in its stretch.
# Contract#find_payment_for_show used to write the first show that asked for it
# onto the payment, and the row then read as that one night's (contract 107,
# 2026-11-08). The link is no longer written; this clears the ones already there.
#
# The sync also renamed a week that had flipped to a shortfall and back for one
# show's fee and the nights in so far ("less $250.00 fee — Nov 5–Nov 6"). A
# settlement nobody has paid or put in a run gets its proper name back
# ("less $750.00 fee — week of Nov 2").
class PeriodSettlementsBelongToNoSingleShow < ActiveRecord::Migration[8.1]
  def up
    cleared = 0
    ContractPayment.where.not(show_id: nil).includes(:contract).find_each do |payment|
      next unless payment.contract&.period_settlement?(payment)

      payment.update_column(:show_id, nil)
      cleared += 1
    end
    say "Cleared the show link on #{cleared} period settlement(s)"

    renamed = 0
    ContractPayment.where(status: "pending", direction: "outgoing", auto_shortfall: false)
                   .where("description LIKE ?", "Ticket revenue less %")
                   .includes(:contract, :payout_contribution).find_each do |payment|
      contract = payment.contract
      next unless contract&.ticket_revenue_minus_fee? && %w[weekly monthly].include?(contract.settlement_cadence)
      next if payment.in_payout_run?

      name = contract.minus_fee_settlement_name(payment)
      next if name == payment.description

      say "Contract #{contract.id}: \"#{payment.description}\" becomes \"#{name}\""
      payment.update_column(:description, name)
      renamed += 1
    end
    say "Renamed #{renamed} settlement(s)"
  end

  def down
    # The links were wrong; nothing to put back.
  end
end

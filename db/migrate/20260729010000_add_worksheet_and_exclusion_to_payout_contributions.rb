# frozen_string_literal: true

# Cash tips are recorded on the staff pay run but never routed through Stripe
# (staff already took their split from the bar tip jar). `excluded_from_payout`
# marks such a recorded-only contribution so it stays out of the payee's transfer
# total and posts no earning ledger entry. `worksheet` keeps the per-day tip /
# cash-tip breakdown that was entered on the pay grid, so a run traces back to the
# days each amount came from.
class AddWorksheetAndExclusionToPayoutContributions < ActiveRecord::Migration[8.1]
  def change
    add_column :payout_contributions, :excluded_from_payout, :boolean, default: false, null: false
    add_column :payout_contributions, :worksheet, :jsonb
  end
end

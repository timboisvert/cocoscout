class AddActCountsToShowPayouts < ActiveRecord::Migration[8.1]
  def change
    # How many acts each payee did on this show, for act-based payout schemes.
    # Keyed by payee ("Person_12", "Group_3", "guest_45") so it survives the
    # line items being destroyed and rebuilt on every recalculation.
    add_column :show_payouts, :act_counts, :jsonb, default: {}, null: false
  end
end

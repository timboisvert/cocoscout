# frozen_string_literal: true

# Closing out a run that's paid except for people with no bank yet: they move
# to one standing "Waiting on bank info" run and the old run closes as paid
# (PayoutRunCloseOut). The paper trail: which run is the waiting one, when a
# run was closed out and by whom, and on every moved line the run it came from.
class AddCloseOutToPayoutRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :payout_batches, :waiting_on_banks, :boolean, default: false, null: false
    add_column :payout_batches, :closed_out_at, :datetime
    add_reference :payout_batches, :closed_out_by, foreign_key: { to_table: :users }, index: false
    add_reference :payout_contributions, :moved_from_batch, foreign_key: { to_table: :payout_batches }, index: true
    add_column :payout_contributions, :moved_at, :datetime
  end
end

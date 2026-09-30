# frozen_string_literal: true

# One open payout run per org. First folds any org still holding more than
# one open draft (an open performer run beside an open staff run, from before
# the merge) into its oldest — see PayoutDraftFolder — then lets the database
# guarantee it from here on. Legacy course-kind drafts are exempt; they no
# longer take new money.
class OneOpenPayoutRunPerOrg < ActiveRecord::Migration[8.1]
  def up
    PayoutDraftFolder.fold_all!

    add_index :payout_batches, :organization_id, unique: true,
              where: "status = 'draft' AND kind <> 'course'",
              name: "idx_payout_batches_one_open_run_per_org"
  end

  def down
    remove_index :payout_batches, name: "idx_payout_batches_one_open_run_per_org"
  end
end

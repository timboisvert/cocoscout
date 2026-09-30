# frozen_string_literal: true

# The org's one open run now carries every kind of money, but a draft left
# from before the merge still wears its old kind — so a run holding show pay
# and staff pay would be titled "Staffing" (or "Performer payouts") on the run
# page and on each payee's bank-deposit receipt. Open drafts become plain
# payout runs. Runs already funded or finished keep the kind they were paid
# under, and legacy course drafts are left alone.
class LabelOpenRunsAsPayouts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE payout_batches
         SET kind = 'payout', updated_at = NOW()
       WHERE status = 'draft'
         AND kind IN ('performer', 'staff_pay', 'balance')
    SQL
  end

  def down
    # The old kinds were labels only; nothing reads them back.
  end
end

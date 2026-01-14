class MigrateOldShowPayoutStatuses < ActiveRecord::Migration[8.1]
  def up
    # Migrate old statuses to new ones:
    # - "draft", "approved", nil, or any other value → "awaiting_payout"
    # - "paid" stays "paid"
    execute <<-SQL
      UPDATE show_payouts
      SET status = 'awaiting_payout'
      WHERE status IS NULL
         OR status NOT IN ('awaiting_payout', 'paid')
    SQL
  end

  def down
    # No way to reverse this - we don't know what the old values were
  end
end

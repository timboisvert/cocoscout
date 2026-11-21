# frozen_string_literal: true

# contract_payment_reminder was the Money → Incoming nudge; invoices and their
# reminders replaced it (337cfab9) and no code reads it any more (Tim,
# 2026-11-20). Nothing references template rows, so the row just goes.
class RemoveContractPaymentReminderTemplate < ActiveRecord::Migration[8.1]
  def up
    execute "DELETE FROM content_templates WHERE key = 'contract_payment_reminder'"
  end

  def down
    # The words live in 20260727130000 and 20260816120000; not restored.
  end
end

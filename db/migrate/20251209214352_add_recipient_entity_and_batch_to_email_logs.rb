class AddRecipientEntityAndBatchToEmailLogs < ActiveRecord::Migration[8.1]
  def change
    add_reference :email_logs, :recipient_entity, polymorphic: true, null: true
    add_reference :email_logs, :email_batch, null: true, foreign_key: true
  end
end

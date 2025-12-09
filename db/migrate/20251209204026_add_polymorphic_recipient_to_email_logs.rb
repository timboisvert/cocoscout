# frozen_string_literal: true

class AddPolymorphicRecipientToEmailLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :email_logs, :recipient_type, :string
    add_column :email_logs, :recipient_id, :integer
    add_index :email_logs, [ :recipient_type, :recipient_id ]
  end
end

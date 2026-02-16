class AllowNullSenderOnMessages < ActiveRecord::Migration[8.1]
  def change
    # Allow null sender for system-generated messages (no human sender)
    change_column_null :messages, :sender_type, true
    change_column_null :messages, :sender_id, true
  end
end

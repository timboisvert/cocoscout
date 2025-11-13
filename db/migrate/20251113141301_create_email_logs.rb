class CreateEmailLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :email_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.string :recipient, null: false
      t.string :subject
      t.text :body
      t.string :mailer_class
      t.string :mailer_action
      t.string :message_id
      t.string :delivery_status, default: "pending"
      t.datetime :sent_at
      t.datetime :delivered_at
      t.text :error_message

      t.timestamps
    end

    add_index :email_logs, :recipient
    add_index :email_logs, :message_id
    add_index :email_logs, :sent_at
  end
end

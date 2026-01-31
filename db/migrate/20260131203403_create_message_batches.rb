class CreateMessageBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :message_batches do |t|
      t.references :sender, polymorphic: true, null: false
      t.references :organization, foreign_key: true, null: true
      t.references :regarding, polymorphic: true, null: true
      t.string :subject, null: false
      t.integer :recipient_count, null: false, default: 0
      t.string :message_type, null: false

      t.timestamps

      t.index [:sender_type, :sender_id]
    end
  end
end

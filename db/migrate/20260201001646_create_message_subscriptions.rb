class CreateMessageSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :message_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :message, null: false, foreign_key: true
      t.datetime :last_read_at
      t.boolean :muted, default: false, null: false

      t.timestamps
    end

    add_index :message_subscriptions, [ :user_id, :message_id ], unique: true
    add_index :message_subscriptions, [ :message_id, :muted ]
  end
end

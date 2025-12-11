# frozen_string_literal: true

class AddCastingFinalization < ActiveRecord::Migration[8.0]
  def change
    # Add finalization timestamp to shows
    add_column :shows, :casting_finalized_at, :datetime

    # Create table to track who was notified about casting
    create_table :show_cast_notifications do |t|
      t.references :show, null: false, foreign_key: true
      t.references :assignable, polymorphic: true, null: false
      t.references :role, null: false, foreign_key: true
      t.integer :notification_type, null: false, default: 0  # 0 = cast, 1 = removed
      t.datetime :notified_at, null: false
      t.text :email_body

      t.timestamps
    end

    add_index :show_cast_notifications,
              [ :show_id, :assignable_type, :assignable_id, :role_id ],
              unique: true,
              name: "idx_show_cast_notifications_unique"
  end
end

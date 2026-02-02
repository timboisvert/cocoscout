class CreateMessageRegards < ActiveRecord::Migration[8.1]
  def change
    create_table :message_regards do |t|
      t.integer :message_id, null: false
      t.string :regardable_type, null: false
      t.integer :regardable_id, null: false

      t.timestamps
    end

    add_index :message_regards, :message_id
    add_index :message_regards, [ :regardable_type, :regardable_id ], name: "index_message_regards_on_regardable"
    add_index :message_regards, [ :message_id, :regardable_type, :regardable_id ], unique: true, name: "index_message_regards_unique"
  end
end

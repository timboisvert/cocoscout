class CreateMessagePolls < ActiveRecord::Migration[8.0]
  def change
    create_table :message_polls do |t|
      t.references :message, null: false, foreign_key: true, index: { unique: true }
      t.string :question, null: false
      t.integer :max_votes, null: false, default: 1
      t.boolean :anonymous, null: false, default: false
      t.datetime :closes_at
      t.boolean :closed, null: false, default: false
      t.timestamps
    end

    create_table :message_poll_options do |t|
      t.references :message_poll, null: false, foreign_key: true
      t.string :text, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :message_poll_options, [ :message_poll_id, :position ]

    create_table :message_poll_votes do |t|
      t.references :message_poll_option, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end

    add_index :message_poll_votes, [ :message_poll_option_id, :user_id ], unique: true, name: "idx_poll_votes_unique"
  end
end

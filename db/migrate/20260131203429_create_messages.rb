class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      # Who sent (User or Person)
      t.references :sender, polymorphic: true, null: false, index: false

      # Who receives (Person or Group - NOT User directly!)
      t.references :recipient, polymorphic: true, null: false, index: false

      # Optional: link to batch if sent to multiple people
      t.bigint :message_batch_id, null: true

      # Organization context (for scoping)
      t.bigint :organization_id, null: true

      # What object this message is "regarding" (polymorphic)
      # Production is derived from this, not stored separately
      t.references :regarding, polymorphic: true, null: true, index: false

      # Threading: parent message for replies
      t.bigint :parent_id, null: true

      # Content (subject only - body uses ActionText)
      t.string :subject, null: false

      # Message categorization
      t.string :message_type, null: false

      # Status tracking
      t.datetime :read_at
      t.datetime :archived_at

      t.timestamps
    end

    # Add foreign keys
    add_foreign_key :messages, :message_batches
    add_foreign_key :messages, :organizations
    add_foreign_key :messages, :messages, column: :parent_id

    # Add indexes separately to avoid conflicts
    add_index :messages, [ :recipient_type, :recipient_id, :read_at ], name: "idx_messages_recipient_read"
    add_index :messages, [ :recipient_type, :recipient_id, :created_at ], name: "idx_messages_recipient_created"
    add_index :messages, [ :regarding_type, :regarding_id ], name: "idx_messages_regarding"
    add_index :messages, :parent_id, name: "idx_messages_parent"
    add_index :messages, :message_batch_id, name: "idx_messages_batch"
    add_index :messages, [ :sender_type, :sender_id ], name: "idx_messages_sender"
  end
end

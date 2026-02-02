class RefactorMessagingArchitecture < ActiveRecord::Migration[8.1]
  def change
    # 1. Create message_recipients table (replaces per-recipient message copies)
    create_table :message_recipients do |t|
      t.references :message, null: false, foreign_key: true
      t.references :recipient, polymorphic: true, null: false  # Person or Group
      t.datetime :read_at
      t.datetime :archived_at
      t.timestamps
    end

    add_index :message_recipients, [ :message_id, :recipient_type, :recipient_id ],
              unique: true, name: 'idx_message_recipients_unique'
    add_index :message_recipients, [ :recipient_type, :recipient_id, :read_at ],
              name: 'idx_message_recipients_unread'

    # 2. Add visibility and direct production/show references to messages
    add_column :messages, :visibility, :string, default: 'private', null: false
    add_reference :messages, :production, foreign_key: true
    add_reference :messages, :show, foreign_key: true

    add_index :messages, [ :visibility, :production_id ], name: 'idx_messages_visibility_production'
    add_index :messages, [ :visibility, :show_id ], name: 'idx_messages_visibility_show'

    # 3. Remove old columns from messages (recipient moved to message_recipients)
    remove_index :messages, name: 'idx_messages_recipient_created'
    remove_index :messages, name: 'idx_messages_recipient_read'
    remove_column :messages, :recipient_id, :bigint
    remove_column :messages, :recipient_type, :string
    remove_column :messages, :read_at, :datetime  # Now per-recipient in message_recipients
    remove_column :messages, :archived_at, :datetime  # Now per-recipient in message_recipients

    # 4. Remove message_batch_id (batches are eliminated)
    remove_index :messages, name: 'idx_messages_batch'
    remove_column :messages, :message_batch_id, :bigint

    # 5. Remove sent_on_behalf_of (replaced by production_id + visibility)
    remove_index :messages, name: 'index_messages_on_sent_on_behalf_of'
    remove_column :messages, :sent_on_behalf_of_id, :integer
    remove_column :messages, :sent_on_behalf_of_type, :string

    # 6. Drop message_batches table
    drop_table :message_batches do |t|
      t.string "message_type", null: false
      t.bigint "organization_id"
      t.integer "recipient_count", default: 0, null: false
      t.bigint "regarding_id"
      t.string "regarding_type"
      t.bigint "sender_id", null: false
      t.string "sender_type", null: false
      t.string "subject", null: false
      t.timestamps
    end

    # 7. Clean up old parent_id column (we use parent_message_id)
    remove_index :messages, name: 'idx_messages_parent' if index_exists?(:messages, :parent_id, name: 'idx_messages_parent')
    remove_column :messages, :parent_id, :bigint if column_exists?(:messages, :parent_id)
  end
end

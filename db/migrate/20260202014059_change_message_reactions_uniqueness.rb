class ChangeMessageReactionsUniqueness < ActiveRecord::Migration[8.1]
  def up
    # Remove duplicate reactions, keeping only the most recent one per user per message
    execute <<-SQL
      DELETE FROM message_reactions
      WHERE id NOT IN (
        SELECT MAX(id)
        FROM message_reactions
        GROUP BY user_id, message_id
      )
    SQL

    # Remove old index if it exists
    remove_index :message_reactions, [ :user_id, :message_id, :emoji ], if_exists: true

    # Add new unique index on just user_id and message_id
    add_index :message_reactions, [ :user_id, :message_id ], unique: true
  end

  def down
    remove_index :message_reactions, [ :user_id, :message_id ], if_exists: true
    add_index :message_reactions, [ :user_id, :message_id, :emoji ], unique: true
  end
end

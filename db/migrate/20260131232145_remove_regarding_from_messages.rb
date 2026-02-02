class RemoveRegardingFromMessages < ActiveRecord::Migration[8.1]
  def change
    # Migrate existing regarding data to message_regards before removing
    reversible do |dir|
      dir.up do
        # Copy existing regarding associations to message_regards
        # Use raw SQL to avoid loading the Message model (which has enum dependencies
        # on columns that may not exist yet at this point in migration history)
        execute <<~SQL
          INSERT INTO message_regards (message_id, regardable_type, regardable_id, created_at, updated_at)
          SELECT id, regarding_type, regarding_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
          FROM messages
          WHERE regarding_type IS NOT NULL AND regarding_id IS NOT NULL
        SQL
      end
    end

    remove_column :messages, :regarding_type, :string
    remove_column :messages, :regarding_id, :integer
  end
end

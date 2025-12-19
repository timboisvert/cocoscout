class RemoveBodyFromEmailLogs < ActiveRecord::Migration[8.1]
  def up
    # Remove the body column - data should be migrated to Active Storage first
    # Run `rails email_logs:migrate_to_active_storage` before this migration
    remove_column :email_logs, :body, :text
  end

  def down
    add_column :email_logs, :body, :text
  end
end

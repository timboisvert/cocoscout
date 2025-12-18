class AddMultiProfileSupport < ActiveRecord::Migration[8.1]
  def change
    # Add default_person_id to users table for multi-profile support
    add_reference :users, :default_person, foreign_key: { to_table: :people }, null: true

    # Add archived_at to people table for soft delete
    add_column :people, :archived_at, :datetime
    add_index :people, :archived_at
  end
end

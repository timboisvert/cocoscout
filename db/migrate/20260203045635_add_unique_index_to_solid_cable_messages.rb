class AddUniqueIndexToSolidCableMessages < ActiveRecord::Migration[8.1]
  def change
    # Rails 8.1 with Solid Cable requires a unique index on id for upsert operations
    # The primary key constraint should suffice, but we need to ensure it exists
    # If solid_cable_messages doesn't have a proper primary key, add unique index on id
    unless index_exists?(:solid_cable_messages, :id, unique: true)
      add_index :solid_cable_messages, :id, unique: true, if_not_exists: true
    end
  end
end

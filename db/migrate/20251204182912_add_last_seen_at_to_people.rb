class AddLastSeenAtToPeople < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :last_seen_at, :datetime
    add_index :people, :last_seen_at
  end
end

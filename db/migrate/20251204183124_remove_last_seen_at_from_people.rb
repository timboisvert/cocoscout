class RemoveLastSeenAtFromPeople < ActiveRecord::Migration[8.1]
  def change
    remove_index :people, :last_seen_at
    remove_column :people, :last_seen_at, :datetime
  end
end

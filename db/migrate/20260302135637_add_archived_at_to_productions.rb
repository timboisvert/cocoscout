class AddArchivedAtToProductions < ActiveRecord::Migration[8.1]
  def change
    add_column :productions, :archived_at, :datetime
    add_index :productions, :archived_at
  end
end

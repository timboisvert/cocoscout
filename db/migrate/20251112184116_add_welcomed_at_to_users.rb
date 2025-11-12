class AddWelcomedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :welcomed_at, :datetime
  end
end

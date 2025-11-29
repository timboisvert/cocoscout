class AddProfileWelcomedAtToPeople < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :profile_welcomed_at, :datetime
  end
end

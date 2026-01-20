class AddSignupBasedCastingToShows < ActiveRecord::Migration[8.1]
  def change
    add_column :shows, :signup_based_casting, :boolean, default: false, null: false  end
end

class AddPublicVisibilityToShows < ActiveRecord::Migration[8.1]
  def change
    add_column :shows, :public_profile_visible, :boolean
  end
end

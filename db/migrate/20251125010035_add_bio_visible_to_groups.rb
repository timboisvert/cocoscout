class AddBioVisibleToGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :groups, :bio_visible, :boolean, default: true, null: false
  end
end

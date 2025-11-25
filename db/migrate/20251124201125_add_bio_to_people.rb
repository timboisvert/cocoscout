class AddBioToPeople < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :bio, :text
    add_column :people, :bio_visible, :boolean, default: true, null: false
  end
end

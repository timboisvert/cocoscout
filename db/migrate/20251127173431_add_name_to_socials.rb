class AddNameToSocials < ActiveRecord::Migration[8.1]
  def change
    add_column :socials, :name, :string
  end
end

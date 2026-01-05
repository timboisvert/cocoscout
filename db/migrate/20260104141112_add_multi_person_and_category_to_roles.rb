class AddMultiPersonAndCategoryToRoles < ActiveRecord::Migration[8.1]
  def change
    add_column :roles, :quantity, :integer, default: 1, null: false
    add_column :roles, :category, :string, default: "performing", null: false

    add_index :roles, :category
  end
end

class AddIsDemoToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :is_demo, :boolean, default: false, null: false
  end
end

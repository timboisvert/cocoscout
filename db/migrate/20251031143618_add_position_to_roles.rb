class AddPositionToRoles < ActiveRecord::Migration[8.1]
  def change
    add_column :roles, :position, :integer
  end
end

class AddAvailabilityModeToPeople < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :availability_mode, :string, null: false, default: "unavailable"
  end
end

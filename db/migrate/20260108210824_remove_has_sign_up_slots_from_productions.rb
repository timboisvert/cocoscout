class RemoveHasSignUpSlotsFromProductions < ActiveRecord::Migration[8.1]
  def change
    remove_column :productions, :has_sign_up_slots, :boolean, default: true, null: false
  end
end

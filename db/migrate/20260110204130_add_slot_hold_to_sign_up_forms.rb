class AddSlotHoldToSignUpForms < ActiveRecord::Migration[8.1]
  def change
    add_column :sign_up_forms, :slot_hold_enabled, :boolean, default: true
    add_column :sign_up_forms, :slot_hold_seconds, :integer, default: 30
  end
end

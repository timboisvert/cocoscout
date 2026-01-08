class ChangeHasSignUpSlotsDefaultToTrue < ActiveRecord::Migration[8.1]
  def change
    change_column_default :productions, :has_sign_up_slots, from: false, to: true
  end
end

class AddPreRegistrationToSignUpForms < ActiveRecord::Migration[8.1]
  def change
    add_column :sign_up_forms, :pre_registration_mode, :string, default: "producers_only", null: false
    add_column :sign_up_forms, :pre_registration_window_value, :integer, default: 45, null: false
    add_column :sign_up_forms, :pre_registration_window_unit, :string, default: "days", null: false
  end
end

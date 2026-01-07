class AddHoldbackVisibleToSignUpForms < ActiveRecord::Migration[8.1]
  def change
    add_column :sign_up_forms, :holdback_visible, :boolean, default: true, null: false
  end
end

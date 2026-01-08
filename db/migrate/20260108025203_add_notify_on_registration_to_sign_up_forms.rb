class AddNotifyOnRegistrationToSignUpForms < ActiveRecord::Migration[8.1]
  def change
    add_column :sign_up_forms, :notify_on_registration, :boolean, default: false, null: false
  end
end

class AddShowRegistrationsToSignUpForms < ActiveRecord::Migration[8.1]
  def change
    add_column :sign_up_forms, :show_registrations, :boolean, default: false
  end
end

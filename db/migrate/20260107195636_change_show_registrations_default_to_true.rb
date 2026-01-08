class ChangeShowRegistrationsDefaultToTrue < ActiveRecord::Migration[8.1]
  def change
    change_column_default :sign_up_forms, :show_registrations, from: false, to: true
  end
end

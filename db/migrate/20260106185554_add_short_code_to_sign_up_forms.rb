class AddShortCodeToSignUpForms < ActiveRecord::Migration[8.1]
  def change
    add_column :sign_up_forms, :short_code, :string
    add_index :sign_up_forms, :short_code, unique: true
  end
end

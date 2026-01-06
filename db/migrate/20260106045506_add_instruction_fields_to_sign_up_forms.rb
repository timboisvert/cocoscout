class AddInstructionFieldsToSignUpForms < ActiveRecord::Migration[8.1]
  def change
    add_column :sign_up_forms, :instruction_text, :text
    add_column :sign_up_forms, :success_text, :text
  end
end

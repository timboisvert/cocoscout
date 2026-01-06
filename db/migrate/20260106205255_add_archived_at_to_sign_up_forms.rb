class AddArchivedAtToSignUpForms < ActiveRecord::Migration[8.1]
  def change
    add_column :sign_up_forms, :archived_at, :datetime
  end
end

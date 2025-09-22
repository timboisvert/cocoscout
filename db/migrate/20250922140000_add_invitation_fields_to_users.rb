class AddInvitationFieldsToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :invitation_code, :string
    add_column :users, :invitation_status, :string
  end
end

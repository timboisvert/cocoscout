class AddDeclinedAtToPersonInvitations < ActiveRecord::Migration[8.1]
  def change
    add_column :person_invitations, :declined_at, :datetime
  end
end

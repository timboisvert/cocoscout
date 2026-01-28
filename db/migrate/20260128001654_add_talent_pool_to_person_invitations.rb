class AddTalentPoolToPersonInvitations < ActiveRecord::Migration[8.1]
  def change
    add_reference :person_invitations, :talent_pool, null: true, foreign_key: true
  end
end

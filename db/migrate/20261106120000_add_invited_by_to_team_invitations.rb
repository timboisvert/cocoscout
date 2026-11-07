# frozen_string_literal: true

# Who sent a team invitation, so the email can say so (the mailer named an
# inviter the record never had, and every invitation failed to send). Like
# GroupInvitation#invited_by: the inviting user's profile.
class AddInvitedByToTeamInvitations < ActiveRecord::Migration[8.1]
  def change
    add_column :team_invitations, :invited_by_person_id, :bigint
    add_index :team_invitations, :invited_by_person_id
  end
end

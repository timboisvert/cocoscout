class AddDeclinedAtToRoleVacancyInvitations < ActiveRecord::Migration[8.1]
  def change
    add_column :role_vacancy_invitations, :declined_at, :datetime
  end
end

class BackfillPersonIdOnOrganizationRoles < ActiveRecord::Migration[8.1]
  def up
    # Backfill person_id for existing OrganizationRoles
    # If user has one profile, use that
    # If user has multiple profiles, use the first one (by created_at)
    OrganizationRole.where(person_id: nil).find_each do |role|
      next unless role.user

      people = role.user.people.where(archived_at: nil).order(:created_at)
      if people.any?
        role.update_column(:person_id, people.first.id)
      end
    end
  end

  def down
    # No-op: we don't want to remove the person_id values
  end
end

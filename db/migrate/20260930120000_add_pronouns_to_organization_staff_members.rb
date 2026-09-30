# frozen_string_literal: true

# Pronouns a manager records for a staff member, shown next to their
# preferred name. Blank falls back to the pronouns the person set on their own
# profile (people.pronouns) — see OrganizationStaffMember#display_pronouns.
class AddPronounsToOrganizationStaffMembers < ActiveRecord::Migration[8.1]
  def change
    add_column :organization_staff_members, :pronouns, :string
  end
end

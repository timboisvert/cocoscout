# frozen_string_literal: true

class CastingTableDraftAssignment < ApplicationRecord
  belongs_to :casting_table
  belongs_to :show
  belongs_to :role
  belongs_to :assignable, polymorphic: true

  validates :assignable_id, uniqueness: { scope: [ :casting_table_id, :show_id, :role_id, :assignable_type ] }

  # Check if this assignment would exceed role quantity
  def role_at_capacity?
    # Get all draft assignments for this show and role
    existing_count = casting_table.casting_table_draft_assignments
                                  .where(show_id: show_id, role_id: role_id)
                                  .where.not(id: id)
                                  .count

    # Also count existing finalized assignments for this show/role
    finalized_count = ShowPersonRoleAssignment.where(show_id: show_id, role_id: role_id).count

    total = existing_count + finalized_count + 1
    total > role.quantity
  end
end

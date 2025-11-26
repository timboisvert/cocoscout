class AuditionEmailAssignment < ApplicationRecord
  belongs_to :audition_cycle
  belongs_to :assignable, polymorphic: true

  validates :assignable_id, uniqueness: { scope: [ :audition_cycle_id, :assignable_type ] }

  # Helper method for backward compatibility
  def person
    assignable if assignable_type == "Person"
  end

  # Get all recipients for this assignment (handles both Person and Group)
  def recipients
    case assignable_type
    when "Person"
      [ assignable ]
    when "Group"
      # Get all group members who have notifications enabled
      assignable.group_memberships.includes(:person).select(&:notifications_enabled?).map(&:person)
    else
      []
    end
  end
end

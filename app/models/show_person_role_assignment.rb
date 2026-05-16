# frozen_string_literal: true

class ShowPersonRoleAssignment < ApplicationRecord
  belongs_to :show
  belongs_to :assignable, polymorphic: true, optional: true
  belongs_to :role

  has_one :show_attendance_record, dependent: :destroy

  validates :role, presence: true
  # Prevent duplicate assignments: same person can't be assigned to same role on same show
  validates :assignable_id, uniqueness: { scope: [ :show_id, :role_id, :assignable_type ], message: "is already assigned to this role" }, if: -> { assignable_id.present? }
  # Must have either an assignable (Person/Group) OR guest_name (for guest assignments)
  validate :has_assignable_or_guest

  # Order assignments by position within a role
  scope :ordered, -> { order(position: :asc) }

  # Assignments that are safe to show to performers / public:
  # either the show's casting has been finalized, or this specific assignable
  # has been individually notified as cast for this show.
  # Used to hide in-progress / draft assignments from performer-facing UIs.
  scope :visible_to_performers, -> {
    joins(:show)
      .where(<<~SQL.squish)
        shows.casting_finalized_at IS NOT NULL
        OR EXISTS (
          SELECT 1 FROM show_cast_notifications scn
          WHERE scn.show_id = show_person_role_assignments.show_id
            AND scn.assignable_type = show_person_role_assignments.assignable_type
            AND scn.assignable_id = show_person_role_assignments.assignable_id
            AND scn.notification_type = 0
        )
      SQL
  }

  # Get the person, handling polymorphic assignable
  def person
    return nil unless assignable_type == "Person"
    assignable
  end

  # Auto-assign position on create
  before_create :assign_position

  # Check if this is a guest assignment (not linked to a Person/Group in the system)
  def guest?
    assignable_id.blank? && guest_name.present?
  end

  # Display name - works for both regular and guest assignments
  def display_name
    guest? ? guest_name : assignable&.name
  end

  # Display initials - works for both regular and guest assignments
  def display_initials
    if guest?
      guest_name.to_s.split.map { |word| word[0] }.join.upcase[0..1]
    else
      assignable&.initials
    end
  end

  # Keep person association for backward compatibility during transition
  def person
    assignable if assignable_type == "Person"
  end

  def person=(value)
    self.assignable = value
  end

  private

  def has_assignable_or_guest
    if assignable_id.blank? && guest_name.blank?
      errors.add(:base, "Must have either an assignable (person/group) or a guest name")
    end
  end

  def assign_position
    return if position.present? && position > 0

    # Find the first available slot within the role's quantity
    max_slots = role&.quantity || 1
    taken_positions = ShowPersonRoleAssignment
      .where(show_id: show_id, role_id: role_id)
      .pluck(:position)
      .compact

    # Find the first available position from 1 to max_slots
    (1..max_slots).each do |pos|
      unless taken_positions.include?(pos)
        self.position = pos
        return
      end
    end

    # All slots are taken - this shouldn't happen if fully_filled? is checked before assignment
    # Set position to 1 as a fallback (will trigger uniqueness validation if truly full)
    self.position = 1
  end
end

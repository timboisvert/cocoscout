# frozen_string_literal: true

class ShowPersonRoleAssignment < ApplicationRecord
  belongs_to :show
  belongs_to :assignable, polymorphic: true
  belongs_to :role

  validates :role, presence: true

  # Order assignments by position within a role
  scope :ordered, -> { order(position: :asc) }

  # Auto-assign position on create
  before_create :assign_position

  # Keep person association for backward compatibility during transition
  def person
    assignable if assignable_type == "Person"
  end

  def person=(value)
    self.assignable = value
  end

  private

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

    # Fallback: if all slots taken, use next available (shouldn't happen if fully_filled? is checked)
    self.position = (taken_positions.max || 0) + 1
  end
end

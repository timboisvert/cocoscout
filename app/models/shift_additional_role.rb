# frozen_string_literal: true

# An extra role a single shift also covers, beyond its primary house_role.
# Lets one assignment satisfy multiple roles (manager + bartender + …).
class ShiftAdditionalRole < ApplicationRecord
  belongs_to :shift
  belongs_to :house_role

  validates :house_role_id, uniqueness: { scope: :shift_id }
  validate :not_the_primary_role

  private

  # An "also covers" role can't duplicate the shift's primary role.
  def not_the_primary_role
    return if shift.nil? || house_role_id.nil?
    return unless house_role_id == shift.house_role_id
    errors.add(:house_role_id, "can't be the same as the shift's primary role")
  end
end

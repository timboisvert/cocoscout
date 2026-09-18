# frozen_string_literal: true

# An extra role a single shift also covers, beyond its primary house_role.
# Lets one assignment satisfy multiple roles (manager + bartender + …).
#
# On a shift that covers several shows, the extra role can be scoped to some of
# them: show_id NULL means every show the shift covers (the original meaning);
# a show_id means only that show, with one row per show it covers. So "also on
# tech, but only for the 9pm show" is one row, and a role is never both — it
# either covers everything or names its shows.
class ShiftAdditionalRole < ApplicationRecord
  belongs_to :shift
  belongs_to :house_role
  belongs_to :show, optional: true

  validates :house_role_id, uniqueness: { scope: %i[shift_id show_id] }
  validate :not_the_primary_role
  validate :show_is_covered_by_the_shift
  validate :not_both_everywhere_and_scoped

  scope :for_all_shows, -> { where(show_id: nil) }

  def all_shows?
    show_id.nil?
  end

  private

  # An "also covers" role can't duplicate the shift's primary role.
  def not_the_primary_role
    return if shift.nil? || house_role_id.nil?
    return unless house_role_id == shift.house_role_id
    errors.add(:house_role_id, "can't be the same as the shift's primary role")
  end

  def show_is_covered_by_the_shift
    return if show_id.nil? || shift.nil?
    return if shift.covered_shows.map(&:id).include?(show_id)

    errors.add(:show, "isn't one of the shows this shift covers")
  end

  # A role that covers every show AND names particular ones would read two ways
  # at once. Reject the mix rather than guess which was meant.
  def not_both_everywhere_and_scoped
    return if shift.nil? || house_role_id.nil?

    siblings = ShiftAdditionalRole.where(shift_id: shift_id, house_role_id: house_role_id).where.not(id: id)
    clash = show_id.nil? ? siblings.where.not(show_id: nil).exists? : siblings.where(show_id: nil).exists?
    errors.add(:show, "— this role already covers every show on the shift") if clash && show_id
    errors.add(:show, "— this role is already scoped to particular shows") if clash && show_id.nil?
  end
end

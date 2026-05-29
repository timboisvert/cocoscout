# frozen_string_literal: true

# A specific Person filling a slot of a Shift. Mirrors the shape of
# ShowPersonRoleAssignment (notified_at / accepted_at / declined_at) so the
# same notify-vs-finalize pattern applies later.
class ShiftAssignment < ApplicationRecord
  belongs_to :shift
  belongs_to :person

  validates :person_id, uniqueness: { scope: :shift_id, message: "is already assigned to this shift" }
  validates :position, numericality: { only_integer: true, greater_than: 0 }

  def notified?
    notified_at.present?
  end

  def accepted?
    accepted_at.present?
  end

  def declined?
    declined_at.present?
  end

  def response_status
    return :accepted if accepted_at.present?
    return :declined if declined_at.present?
    :pending
  end
end

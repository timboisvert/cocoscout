# frozen_string_literal: true

# A specific Person filling a slot of a Shift. Mirrors the shape of
# ShowPersonRoleAssignment (notified_at / accepted_at / declined_at) so the
# same notify-vs-finalize pattern applies later.
class ShiftAssignment < ApplicationRecord
  belongs_to :shift
  belongs_to :person
  has_one :staff_time_entry, dependent: :destroy

  validates :person_id, uniqueness: { scope: :shift_id, message: "is already assigned to this shift" }
  validates :position, numericality: { only_integer: true, greater_than: 0 }

  # "Can't make it" declines (staff-initiated), for a manager heads-up.
  scope :declined, -> { where.not(declined_at: nil) }
  # Still standing. A declined assignment stays on the record — the manager has
  # to see who dropped and why — but it staffs nothing, so anything counting
  # coverage counts only these.
  scope :active, -> { where(declined_at: nil) }

  # "I can't make it": the row stays, declined, as the schedule's picture of
  # the hole, and a ShiftVacancy opens around it (who dropped and why,
  # finding cover, covered). The vacancy tells the managers.
  def decline!(reason: nil)
    transaction do
      update!(declined_at: Time.current, accepted_at: nil, decline_reason: reason.to_s.strip.presence)
      unless shift.shift_vacancies.active.exists?(vacated_by_id: person_id)
        shift.shift_vacancies.create!(vacated_by: person, vacated_at: declined_at, reason: decline_reason)
      end
    end
  end

  # The columns alone. "I'm back on" goes through the vacancy (reclaim!),
  # which calls this and tells the managers.
  def undo_decline!
    update!(declined_at: nil, decline_reason: nil)
  end

  # The vacancy this decline opened, while it's still being dealt with.
  def active_vacancy
    shift.shift_vacancies.find { |v| v.active? && v.vacated_by_id == person_id }
  end

  def accepted?
    accepted_at.present?
  end

  def declined?
    declined_at.present?
  end

  def active?
    declined_at.nil?
  end

  def response_status
    return :accepted if accepted_at.present?
    return :declined if declined_at.present?
    :pending
  end
end

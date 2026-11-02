# frozen_string_literal: true

# A shift someone said they can't make, and what became of it: the staffing
# counterpart of RoleVacancy (Tim, 2026-11-02: the performer flow, for staff).
#
# The declined ShiftAssignment row stays as the schedule's picture of the hole
# (the chips, the counts, the status bar and Home all read it from preloaded
# rows with no extra queries). This record is the work around it: who dropped
# and why, invitations out, who covered it, or that the manager isn't filling
# it. One rule holds the two together: a declined row exists exactly while a
# vacancy for that shift and person is active, and every way of closing one
# here resolves the row.
class ShiftVacancy < ApplicationRecord
  belongs_to :shift
  belongs_to :vacated_by, class_name: "Person"
  belongs_to :filled_by, class_name: "Person", optional: true
  belongs_to :closed_by, class_name: "User", optional: true
  has_many :invitations, class_name: "ShiftVacancyInvitation", dependent: :destroy
  has_one :organization, through: :shift

  enum :status, {
    open: "open",
    finding_replacement: "finding_replacement",
    not_filling: "not_filling",
    filled: "filled",
    cancelled: "cancelled"
  }

  scope :active, -> { where(status: %w[open finding_replacement]) }
  scope :closed, -> { where(status: %w[not_filling filled cancelled]) }
  scope :upcoming, -> { joins(:shift).where("shifts.ends_at >= ?", Time.current) }

  validates :vacated_at, presence: true

  after_commit :notify_team_of_creation, on: :create

  def active?
    open? || finding_replacement?
  end

  # The dropped row, from the shift's loaded rows when they are loaded.
  def declined_assignment
    shift.shift_assignments.find { |a| a.person_id == vacated_by_id && a.declined? }
  end

  # Someone covers it: the dropped row goes and the replacement is on the
  # shift. Accepted and told when they claimed it themselves (so Notify
  # updates leaves them alone); neither when a manager put them on by hand,
  # since they still need telling and the week should show it as one update
  # to send.
  def fill!(person, by: nil, accepted: false)
    return false unless active?

    stamp = Time.current
    transaction do
      declined_row&.destroy!
      unless shift.shift_assignments.active.exists?(person_id: person.id)
        shift.shift_assignments.create!(person: person, position: next_position,
                                        accepted_at: (stamp if accepted), notified_at: (stamp if accepted))
      end
      update!(status: :filled, filled_by: person, filled_at: stamp, closed_at: stamp, closed_by: by)
    end
    ShiftVacancyNotificationJob.perform_later(id, "filled")
    true
  end

  # A manager put someone on the shift by hand (the picker, a Regulars apply)
  # while a vacancy was open: that covers the oldest one. Called by the
  # places that assign, never a callback: a merge copies rows across and
  # must not count as cover.
  def self.fill_from_assignment!(assignment, by: nil)
    vacancy = active.where(shift_id: assignment.shift_id).where.not(vacated_by_id: assignment.person_id)
                    .order(:vacated_at, :id).first
    return nil unless vacancy

    stamp = Time.current
    vacancy.transaction do
      vacancy.send(:declined_row)&.destroy!
      vacancy.update!(status: :filled, filled_by: assignment.person, filled_at: stamp, closed_at: stamp, closed_by: by)
    end
    ShiftVacancyNotificationJob.perform_later(vacancy.id, "filled")
    vacancy
  end

  # The manager isn't filling it: the hole closes, so the red goes, and the
  # staffer sees "they're not filling it". They can't take it back after
  # this (RoleVacancy lets a performer reclaim from not_filling; here the row
  # is gone); the manager can put them back on through the picker.
  def mark_not_filling!(by: nil)
    return false unless active?

    transaction do
      declined_row&.destroy!
      update!(status: :not_filling, closed_at: Time.current, closed_by: by)
    end
    true
  end

  # They can make it after all, or the manager put them back: the row stands
  # again and the managers hear.
  def reclaim!(by: nil)
    return false unless active?

    transaction do
      row = declined_row
      row ? row.undo_decline! : shift.shift_assignments.create!(person: vacated_by, position: next_position)
      update!(status: :cancelled, closed_at: Time.current, closed_by: by)
    end
    ShiftVacancyNotificationJob.perform_later(id, "reclaimed")
    true
  end

  # The hole went away some other way (the manager removed the row): closed,
  # with no notice. The caller deals with the row.
  def cancel!(by: nil)
    return false unless active?

    update!(status: :cancelled, closed_at: Time.current, closed_by: by)
  end

  def mark_finding_replacement!
    update!(status: :finding_replacement) if open?
  end

  # Not the one who dropped it, not someone already on the shift, not twice.
  def can_invite?(person)
    active? && person.id != vacated_by_id &&
      !invitations.exists?(person_id: person.id) &&
      !shift.shift_assignments.active.exists?(person_id: person.id)
  end

  def pending_invitations
    invitations.pending
  end

  def claimed_invitation
    invitations.claimed.first
  end

  private

  def declined_row
    shift.shift_assignments.declined.find_by(person_id: vacated_by_id)
  end

  def next_position
    (shift.shift_assignments.maximum(:position) || 0) + 1
  end

  # The chosen managers hear about it (Staffing → Settings → Notifications);
  # not for a shift that's already over.
  def notify_team_of_creation
    return if shift.ends_at < Time.current

    row = declined_row
    ShiftDeclinedNotificationJob.perform_later(row.id) if row
  end
end

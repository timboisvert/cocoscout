# frozen_string_literal: true

class ShowAttendanceRecord < ApplicationRecord
  STATUSES = %w[unknown present absent excused].freeze

  belongs_to :show
  belongs_to :show_person_role_assignment, optional: true
  belongs_to :sign_up_registration, optional: true
  belongs_to :person, optional: true  # For walk-ins

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :show_id, presence: true
  validate :has_valid_attendee_reference

  scope :present, -> { where(status: "present") }
  scope :absent, -> { where(status: "absent") }
  scope :excused, -> { where(status: "excused") }
  scope :unknown, -> { where(status: "unknown") }

  # Auto-populate checked_in_at when marked present
  before_save :set_checked_in_at

  def present?
    status == "present"
  end

  def absent?
    status == "absent"
  end

  def excused?
    status == "excused"
  end

  def unknown?
    status == "unknown"
  end

  def attended?
    present?
  end

  # Returns the person associated with this record (from any source)
  def attendee
    if show_person_role_assignment_id.present?
      show_person_role_assignment.person
    elsif sign_up_registration_id.present?
      sign_up_registration.person
    else
      person
    end
  end

  private

  def has_valid_attendee_reference
    refs = [
      show_person_role_assignment_id,
      sign_up_registration_id,
      person_id
    ].compact

    if refs.empty?
      errors.add(:base, "Must have a role assignment, sign-up registration, or person (walk-in)")
    end
  end

  def set_checked_in_at
    if status_changed? && present? && checked_in_at.nil?
      self.checked_in_at = Time.current
    end
  end
end

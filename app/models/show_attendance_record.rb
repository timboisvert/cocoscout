# frozen_string_literal: true

class ShowAttendanceRecord < ApplicationRecord
  STATUSES = %w[unknown present absent late excused].freeze

  belongs_to :show
  belongs_to :show_person_role_assignment, optional: true
  belongs_to :sign_up_registration, optional: true

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :show_id, presence: true
  validate :has_either_assignment_or_registration

  scope :present, -> { where(status: "present") }
  scope :absent, -> { where(status: "absent") }
  scope :late, -> { where(status: "late") }
  scope :excused, -> { where(status: "excused") }
  scope :unknown, -> { where(status: "unknown") }

  private

  def has_either_assignment_or_registration
    if show_person_role_assignment_id.blank? && sign_up_registration_id.blank?
      errors.add(:base, "Must have either a role assignment or sign-up registration")
    end
  end

  def present?
    status == "present"
  end

  def absent?
    status == "absent"
  end

  def late?
    status == "late"
  end

  def excused?
    status == "excused"
  end

  def unknown?
    status == "unknown"
  end

  def attended?
    present? || late?
  end
end

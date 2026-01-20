# frozen_string_literal: true

class ShowAttendanceRecord < ApplicationRecord
  STATUSES = %w[unknown present absent late excused].freeze

  belongs_to :show
  belongs_to :show_person_role_assignment

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :show_person_role_assignment_id, uniqueness: { scope: :show_id }

  scope :present, -> { where(status: "present") }
  scope :absent, -> { where(status: "absent") }
  scope :late, -> { where(status: "late") }
  scope :excused, -> { where(status: "excused") }
  scope :unknown, -> { where(status: "unknown") }

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

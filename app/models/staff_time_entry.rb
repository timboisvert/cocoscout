# frozen_string_literal: true

# A unit of worked time logged by a staff member — either confirming (and
# optionally adjusting) a scheduled shift, or self-logging ad-hoc work they did
# on their own. Managers pull unpaid entries into a pay run; once pulled, the
# entry is tied to that batch and marked paid so it can't be paid twice.
class StaffTimeEntry < ApplicationRecord
  SOURCES = %w[shift manual].freeze

  belongs_to :organization
  belongs_to :person
  belongs_to :shift_assignment, optional: true
  belongs_to :payout_batch, optional: true

  has_one :shift, through: :shift_assignment

  validates :source, inclusion: { in: SOURCES }
  validates :started_at, :ended_at, presence: true
  validate :ends_after_start
  validates :hours, numericality: { greater_than: 0 }

  before_validation :compute_hours

  scope :unpaid, -> { where(payout_batch_id: nil) }
  scope :paid, -> { where.not(payout_batch_id: nil) }
  scope :for_person, ->(person) { where(person_id: person) }
  scope :recent, ->(range) { where(started_at: range) }
  scope :chronological, -> { order(:started_at) }

  def paid?
    payout_batch_id.present?
  end

  def compute_hours
    return if started_at.blank? || ended_at.blank?

    self.hours = ((ended_at - started_at) / 1.hour).round(2)
  end

  private

  def ends_after_start
    return if started_at.blank? || ended_at.blank?

    errors.add(:ended_at, "must be after the start time") if ended_at <= started_at
  end
end

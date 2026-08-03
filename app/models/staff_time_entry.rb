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
  belongs_to :approved_by, class_name: "User", optional: true
  belongs_to :offline_paid_by, class_name: "User", optional: true
  # The role this work was done as — the thing that prices the hours. Shift
  # confirmations inherit it from the shift; self-logged entries pick it.
  # Optional so genuinely role-less work falls back to the person's default rate.
  belongs_to :house_role, optional: true

  has_one :shift, through: :shift_assignment

  validates :source, inclusion: { in: SOURCES }
  validates :started_at, :ended_at, presence: true
  validate :ends_after_start
  validates :hours, numericality: { greater_than: 0 }
  validate :house_role_belongs_to_org

  before_validation :compute_hours

  # "Paid" is either pulled into a pay run (payout_batch) or hand-marked as
  # settled outside CocoScout (offline_paid_at) — both make the entry
  # un-pullable and locked.
  scope :unpaid, -> { where(payout_batch_id: nil, offline_paid_at: nil) }
  scope :paid, -> { where.not(payout_batch_id: nil).or(where.not(offline_paid_at: nil)) }
  scope :pending, -> { where(approved_at: nil, payout_batch_id: nil, offline_paid_at: nil) }
  scope :approved, -> { where.not(approved_at: nil).where(payout_batch_id: nil, offline_paid_at: nil) }
  # Everything a manager has signed off on, whether or not it's since been paid —
  # backs the "view approved hours" history.
  scope :signed_off, -> { where.not(approved_at: nil) }
  scope :for_person, ->(person) { where(person_id: person) }
  scope :recent, ->(range) { where(started_at: range) }
  scope :chronological, -> { order(:started_at) }

  def paid?
    payout_batch_id.present? || offline_paid_at.present?
  end

  # Settled by hand outside CocoScout (payroll check, cash, …) rather than
  # through a pay run. No money moved through us — the mark is the record.
  def paid_offline?
    offline_paid_at.present? && payout_batch_id.nil?
  end

  def approved?
    approved_at.present?
  end

  # A worker's entry starts life "pending review", becomes "approved" once a
  # manager signs off, and finally "paid" when it's pulled into a pay run
  # (or marked as already paid outside CocoScout).
  def status
    return "paid" if paid?
    return "approved" if approved?

    "pending"
  end

  def status_label
    return "Paid outside CocoScout" if paid_offline?

    { "paid" => "Paid", "approved" => "Approved", "pending" => "Pending review" }[status]
  end

  # Record that these hours were already settled outside CocoScout. Marking
  # implies sign-off, so an entry straight from the pending queue gets approved
  # in the same stroke. paid_at is set so the entry reads as paid everywhere
  # the batch-paid ones do.
  # amount_cents records what was actually paid when the external system knows
  # better than our rates (historical imports); left nil, the hours price at
  # the member's rate as usual.
  def mark_paid_offline!(by_user, note: nil, paid_on: nil, amount_cents: nil)
    paid_time = paid_on.present? ? (Date.parse(paid_on.to_s).noon rescue Time.current) : Time.current
    update!(
      offline_paid_at: paid_time,
      offline_paid_by: by_user,
      offline_payment_note: note.presence,
      offline_amount_cents: amount_cents,
      paid_at: paid_time,
      approved_at: approved_at || Time.current,
      approved_by: approved_by || by_user
    )
  end

  # Undo a mistaken offline-paid mark. The approval sticks — the hours were
  # still signed off — so the entry lands back in "approved", pullable again.
  def unmark_paid_offline!
    update!(offline_paid_at: nil, offline_paid_by: nil, offline_payment_note: nil, offline_amount_cents: nil, paid_at: nil)
  end

  def compute_hours
    return if started_at.blank? || ended_at.blank?

    self.hours = ((ended_at - started_at) / 1.hour).round(2)
  end

  # The role that prices these hours: the entry's own role, else the shift's
  # (covers rows that predate the house_role column).
  def effective_house_role
    house_role || shift&.house_role
  end

  private

  def ends_after_start
    return if started_at.blank? || ended_at.blank?

    errors.add(:ended_at, "must be after the start time") if ended_at <= started_at
  end

  def house_role_belongs_to_org
    return if house_role_id.blank? || organization.blank?

    errors.add(:house_role, "isn't one of this organization's roles") unless organization.house_roles.exists?(id: house_role_id)
  end
end

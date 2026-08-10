# frozen_string_literal: true

# PersonAdvance represents an early payment to a performer before their show.
# The advance amount is later subtracted from their actual show payout.
#
# Lifecycle:
# 1. Created (issued) - amount decided, not yet paid
# 2. Paid - money sent to the performer
# 3. Applied - subtracted from a future show payout (can be partial)
# 4. Settled - fully applied to payouts (or written off)
#
class PersonAdvance < ApplicationRecord
  STATUSES = %w[pending partial settled written_off].freeze
  ADVANCE_TYPES = %w[show general].freeze
  # "stripe" is the internal marker for an advance settled through a payout run;
  # it is stored, never hand-picked. MANUAL_PAYMENT_METHODS is what a manager can
  # choose when recording an offline payment.
  PAYMENT_METHODS = %w[cash check other stripe].freeze
  MANUAL_PAYMENT_METHODS = %w[cash check other].freeze

  belongs_to :person
  belongs_to :production
  belongs_to :show, optional: true  # Only for show-specific advances
  belongs_to :issued_by, class_name: "User"
  belongs_to :paid_by, class_name: "User", optional: true

  has_many :advance_applications, class_name: "AdvanceRecovery", foreign_key: :person_advance_id, dependent: :destroy
  has_many :show_payout_line_items, through: :advance_applications
  has_many :payout_ledger_entries, as: :source, dependent: :destroy
  # This advance's slot in a payout run, once issued into one.
  has_one :payout_contribution, as: :source, dependent: :destroy

  validates :original_amount, presence: true, numericality: { greater_than: 0 }
  validates :remaining_balance, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :advance_type, inclusion: { in: ADVANCE_TYPES }
  validates :issued_at, presence: true
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }, allow_nil: true
  validate :show_required_for_show_type
  validate :show_belongs_to_production

  # Status scopes
  scope :pending, -> { where(status: "pending") }
  scope :partial, -> { where(status: "partial") }
  scope :not_settled, -> { where(status: %w[pending partial]) }
  scope :settled, -> { where(status: "settled") }
  scope :written_off, -> { where(status: "written_off") }

  # Payment scopes
  scope :paid, -> { where.not(paid_at: nil) }
  scope :unpaid, -> { where(paid_at: nil) }

  # Other scopes
  scope :for_show, ->(show) { where(show: show) }
  scope :general, -> { where(advance_type: "general") }
  scope :show_specific, -> { where(advance_type: "show") }
  scope :by_issued_at, -> { order(issued_at: :desc) }

  # Aliases for backwards compatibility
  scope :outstanding, -> { not_settled }
  scope :fully_recovered, -> { settled }

  before_validation :set_remaining_balance, on: :create

  # Whether this advance has been issued into a payout run.
  def in_payout_run?
    payout_contribution.present?
  end

  # Marks the advance paid when its payout run pays out (called from
  # PayoutBatchService.settle_item_sources!). Display-only — the PayoutBatchItem
  # posts the single debiting `payout` ledger entry (which drives the payee's
  # balance negative), and future earnings net against it. No ledger entry here.
  def mark_paid_via_payout_run!(reference_id: nil)
    update!(paid_at: Time.current, payment_method: "stripe")
  end

  # The run that paid this came back — see PayoutBatchItem#mark_returned!.
  # Only undoes a payout-run payment; anything handed over another way stands.
  def mark_unpaid_via_payout_run!
    return unless payment_method == "stripe"

    update!(paid_at: nil, payment_method: nil)
  end

  # Payment status
  def paid?
    paid_at.present?
  end

  def unpaid?
    !paid?
  end

  # Application status (whether it's been subtracted from payouts)
  def settled?
    status == "settled"
  end

  def not_settled?
    %w[pending partial].include?(status)
  end

  # Alias for backwards compatibility
  def outstanding?
    not_settled?
  end

  def fully_recovered?
    settled?
  end

  # How much has been applied to payouts
  def applied_amount
    original_amount - remaining_balance
  end

  # Aliases for view-friendly terminology
  alias_method :repaid_amount, :applied_amount
  alias_method :recovered_amount, :applied_amount

  def fully_repaid?
    settled?
  end

  def fully_repaid_at
    fully_recovered_at
  end

  # Human-readable status for display
  def display_status
    if !paid?
      "Awaiting Payment"
    elsif settled?
      "Settled"
    elsif remaining_balance < original_amount
      "Partially Applied"
    else
      "Paid"
    end
  end

  # Mark the advance as paid (money sent to the person)
  def mark_paid!(user, method:, notes: nil)
    update!(
      paid_at: Time.current,
      paid_by: user,
      payment_method: method,
      notes: [ self.notes, notes ].compact.join("\n").presence
    )
  end

  # Unmark as paid
  def unmark_paid!
    update!(
      paid_at: nil,
      paid_by: nil,
      payment_method: nil
    )
  end

  # Apply (deduct) an amount from this advance toward a payout
  # Returns the actual amount applied (may be less if remaining_balance is lower)
  def apply!(amount, show_payout_line_item)
    return 0 if amount <= 0 || remaining_balance <= 0

    actual_amount = [ amount, remaining_balance ].min

    transaction do
      # Create the application record
      advance_applications.create!(
        show_payout_line_item: show_payout_line_item,
        amount: actual_amount
      )

      # Update remaining balance
      new_balance = remaining_balance - actual_amount
      new_status = if new_balance <= 0
        self.fully_recovered_at = Time.current
        "settled"
      else
        "partial"
      end

      update!(remaining_balance: new_balance, status: new_status)
    end

    actual_amount
  end

  # Alias for backwards compatibility
  alias_method :recover!, :apply!

  # Write off the remaining balance (don't deduct from future payouts)
  def write_off!(notes: nil)
    return false unless not_settled?

    update!(
      status: "written_off",
      notes: [ self.notes, "Written off: #{notes}" ].compact.join("\n")
    )
  end

  private

  def set_remaining_balance
    self.remaining_balance ||= original_amount
  end

  def show_required_for_show_type
    if advance_type == "show" && show.nil?
      errors.add(:show, "is required for show-specific advances")
    end
  end

  def show_belongs_to_production
    if show.present? && show.production_id != production_id
      errors.add(:show, "must belong to the same production")
    end
  end
end

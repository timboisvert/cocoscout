# frozen_string_literal: true

class CourseOfferingPayoutLineItem < ApplicationRecord
  belongs_to :course_offering_payout
  belongs_to :payee, polymorphic: true, optional: true
  belongs_to :manually_paid_by, class_name: "User", optional: true
  has_one :course_offering, through: :course_offering_payout

  validates :amount_cents, presence: true

  scope :paid, -> { where(manually_paid: true) }
  scope :unpaid, -> { where(manually_paid: false) }

  def paid?
    manually_paid?
  end

  def mark_paid!(user:, method:, notes: nil)
    update!(
      manually_paid: true,
      manually_paid_at: Time.current,
      manually_paid_by: user,
      paid_at: Time.current,
      payment_method: method,
      payment_notes: notes
    )

    # Sync to related ContractPayment if this line item is for a contract
    sync_to_contract_payment(user, method, notes)
  end

  # Called when the payout run carrying this line pays out (PayoutBatchService.
  # settle_item_sources!): mark the line paid via Stripe and settle the parent
  # payout once every line is. Display/traceability only — the run's item posts
  # the single debiting ledger entry.
  def mark_paid_via_payout_run!(reference_id: nil)
    unless paid?
      update_columns(manually_paid: true, manually_paid_at: Time.current,
                     paid_at: Time.current, payment_method: "stripe")
    end
    course_offering_payout.settle_if_fully_paid!
  end

  # The run that paid this line came back — only undoes a Stripe-run payment,
  # never money a manager recorded by hand.
  def mark_unpaid_via_payout_run!
    return unless manually_paid? && payment_method == "stripe" && manually_paid_by_id.nil?

    update_columns(manually_paid: false, manually_paid_at: nil, paid_at: nil, payment_method: nil)
    payout = course_offering_payout
    payout.update_columns(status: "calculated", paid_at: nil) if payout.paid?
  end

  def formatted_amount
    return "$0" if amount_cents.nil? || amount_cents.zero?
    dollars = amount_cents / 100.0
    if dollars == dollars.to_i
      "$#{dollars.to_i}"
    else
      "$#{'%.2f' % dollars}"
    end
  end

  def payee_name
    return label if payee.nil?
    payee.respond_to?(:name) ? payee.name : label
  end

  private

  def sync_to_contract_payment(user, method, notes)
    contract = course_offering&.contract
    return unless contract && payee_type == "Contractor"

    # Find matching outgoing ContractPayments for this contractor
    contract.contract_payments.where(
      direction: "outgoing",
      status: "pending"
    ).each do |payment|
      # Match by contractor name or ID if we can
      next unless payment_matches_contractor?(payment)

      payment.mark_paid!(
        paid_on: paid_at.to_date,
        method: method,
        reference: "Course offering payout",
        amount: amount_cents / 100.0
      )
    end
  end

  def payment_matches_contractor?(payment)
    # Payment description might contain contractor name
    return false unless payment.description

    contractor_name = payee.name if payee.is_a?(Contractor)
    return false unless contractor_name

    payment.description.downcase.include?(contractor_name.downcase) ||
      payment.contract.contractor_name.downcase.include?(contractor_name.downcase)
  end
end

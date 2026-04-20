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
end

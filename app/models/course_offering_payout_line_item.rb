# frozen_string_literal: true

class CourseOfferingPayoutLineItem < ApplicationRecord
  belongs_to :course_offering_payout
  belongs_to :payee, polymorphic: true, optional: true
  belongs_to :manually_paid_by, class_name: "User", optional: true

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

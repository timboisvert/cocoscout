# frozen_string_literal: true

class CourseRegistration < ApplicationRecord
  belongs_to :course_offering
  belongs_to :person
  belongs_to :user, optional: true

  has_one :production, through: :course_offering

  enum :status, {
    pending: "pending",
    confirmed: "confirmed",
    cancelled: "cancelled",
    refunded: "refunded"
  }, default: :pending

  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :registered_at, presence: true

  scope :active, -> { where(status: %w[confirmed pending]) }
  scope :confirmed, -> { where(status: "confirmed") }
  scope :pending, -> { where(status: "pending") }

  def formatted_amount
    return "$0" if amount_cents.nil? || amount_cents.zero?
    dollars = amount_cents / 100.0
    if dollars == dollars.to_i
      "$#{dollars.to_i}"
    else
      "$#{'%.2f' % dollars}"
    end
  end

  def confirm!(payment_intent_id: nil)
    update!(
      status: :confirmed,
      paid_at: Time.current,
      stripe_payment_intent_id: payment_intent_id
    )
  end

  def cancel!
    update!(status: :cancelled, cancelled_at: Time.current)
    cleanup_questionnaire_invitation
  end

  def refund!
    update!(status: :refunded, refunded_at: Time.current)
    cleanup_questionnaire_invitation
  end

  private

  def cleanup_questionnaire_invitation
    return unless course_offering.questionnaire_id?

    QuestionnaireInvitation.where(
      questionnaire_id: course_offering.questionnaire_id,
      invitee: person,
      context: course_offering
    ).destroy_all
  end
end

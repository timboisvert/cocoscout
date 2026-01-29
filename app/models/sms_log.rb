# frozen_string_literal: true

class SmsLog < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :organization, optional: true
  belongs_to :production, optional: true

  validates :phone, presence: true
  validates :message, presence: true
  validates :sms_type, presence: true
  validates :status, presence: true

  SMS_TYPES = %w[ show_cancellation vacancy_notification ].freeze
  STATUSES = %w[ pending sent failed ].freeze

  validates :sms_type, inclusion: { in: SMS_TYPES }
  validates :status, inclusion: { in: STATUSES }

  scope :sent, -> { where(status: "sent") }
  scope :failed, -> { where(status: "failed") }
  scope :pending, -> { where(status: "pending") }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }
  scope :for_type, ->(type) { where(sms_type: type) }

  def sent?
    status == "sent"
  end

  def failed?
    status == "failed"
  end

  def pending?
    status == "pending"
  end

  # Format phone for display
  def formatted_phone
    return phone unless phone.present?

    digits = phone.gsub(/\D/, "")
    return phone unless digits.length == 10

    "(#{digits[0..2]}) #{digits[3..5]}-#{digits[6..9]}"
  end

  # Human-readable type name
  def type_display
    sms_type.titleize
  end
end

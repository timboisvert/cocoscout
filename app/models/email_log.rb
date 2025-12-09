# frozen_string_literal: true

class EmailLog < ApplicationRecord
  belongs_to :user
  belongs_to :recipient, polymorphic: true, optional: true

  validates :recipient, presence: true

  scope :sent, -> { where.not(sent_at: nil) }
  scope :delivered, -> { where(delivery_status: "delivered") }
  scope :failed, -> { where(delivery_status: "failed") }
  scope :for_user, ->(user) { where(user: user) }
  scope :recent, -> { order(sent_at: :desc) }
  scope :for_recipient, ->(recipient) { where(recipient_type: recipient.class.name, recipient_id: recipient.id) }

  def delivered?
    delivery_status == "delivered"
  end

  def failed?
    delivery_status == "failed"
  end

  def pending?
    delivery_status == "pending"
  end
end

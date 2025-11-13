class EmailLog < ApplicationRecord
  belongs_to :user

  validates :recipient, presence: true

  scope :sent, -> { where.not(sent_at: nil) }
  scope :delivered, -> { where(delivery_status: "delivered") }
  scope :failed, -> { where(delivery_status: "failed") }
  scope :for_user, ->(user) { where(user: user) }
  scope :recent, -> { order(sent_at: :desc) }

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

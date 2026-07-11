# frozen_string_literal: true

# A batch of payouts an organization sends at once through Stripe Connect.
class PayoutBatch < ApplicationRecord
  STATUSES = %w[draft funding funded processing completed failed canceled].freeze
  TRIGGERS = %w[manual scheduled].freeze

  belongs_to :organization
  belongs_to :created_by, class_name: "User", optional: true
  has_many :items, class_name: "PayoutBatchItem", dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :trigger, inclusion: { in: TRIGGERS }

  scope :recent, -> { order(created_at: :desc) }

  def recalculate_total!
    update!(total_cents: items.sum(:amount_cents))
  end

  def paid_total_cents
    items.where(status: "paid").sum(:amount_cents)
  end

  def completed?
    status == "completed"
  end

  def display_status
    status.titleize
  end
end

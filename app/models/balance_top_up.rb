# frozen_string_literal: true

# Money the theater added to its CocoScout balance from its bank
# (BalanceTopUpService). refund_request holds a refund waiting on it:
# { "order_id", "ticket_ids", "keep_fees", "reason", "user_id" }.
class BalanceTopUp < ApplicationRecord
  STATUSES = %w[pending succeeded failed].freeze

  belongs_to :organization
  belongs_to :requested_by, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }

  scope :succeeded, -> { where(status: "succeeded") }
end

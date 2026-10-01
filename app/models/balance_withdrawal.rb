# frozen_string_literal: true

# Money the theater moved from its CocoScout balance to its own bank: one
# Stripe transfer to the theater's connected account, which Stripe pays out to
# the bank. Made by a manager, or automatically when the theater turned that
# on (see BalanceWithdrawalService). A failed one gives the money back to the
# balance.
class BalanceWithdrawal < ApplicationRecord
  STATUSES = %w[pending sent failed].freeze

  belongs_to :organization
  belongs_to :requested_by, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }

  scope :not_failed, -> { where.not(status: "failed") }
end

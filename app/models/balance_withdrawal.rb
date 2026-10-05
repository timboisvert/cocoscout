# frozen_string_literal: true

# Money the theater moved from its CocoScout balance to its own bank: one
# Stripe transfer to the theater's connected account, which Stripe pays out to
# the bank. Made by a manager, or automatically when the theater turned that
# on (see BalanceWithdrawalService).
#
#   pending        — being sent
#   sent           — in the theater's Stripe account, on its way to the bank
#   paid           — Stripe's payout reached the bank
#   bank_rejected  — the bank turned the payout down; the money waits in the
#                    theater's Stripe account until they fix their bank
#   failed         — the transfer never happened; the money stayed with us
#   reversed       — the transfer was taken back; the money is with us again
#
# Failed and reversed ones gave the money back to the balance.
class BalanceWithdrawal < ApplicationRecord
  STATUSES = %w[pending sent paid bank_rejected failed reversed].freeze
  RETURNED = %w[failed reversed].freeze

  belongs_to :organization
  belongs_to :requested_by, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }

  scope :not_failed, -> { where.not(status: RETURNED) }

  # How it stands, in words a theater reads.
  def status_label
    case status
    when "pending" then "Sending"
    when "sent" then "On its way to your bank"
    when "paid" then "In your bank"
    when "bank_rejected" then "Your bank turned it down"
    when "failed" then "Didn't go through"
    when "reversed" then "Came back to your balance"
    end
  end
end

# frozen_string_literal: true

# One day's money, settled or not (Books V1.3, plan §9.2). The pieces of the
# day (its shows, door cash) are read live by SettleUp; this row holds the
# day's state: settled when every piece was checked, and who did it; reopened
# with a reason when something had to change (§9.7). The door cash count
# lives here too.
#
# Which day a time belongs to is the organization's call (§9.6):
#   smart     a day starts at settlement_day_starts_at (6 am) and runs until
#             the next morning, so a 12:15 am bar round is still Friday's
#   calendar  strictly by the date, at midnight
class SettlementDay < ApplicationRecord
  STATUSES = %w[open settled].freeze
  MODES = %w[smart calendar].freeze

  belongs_to :organization
  has_many :tip_shares, dependent: :destroy
  belongs_to :settled_by, class_name: "User", optional: true
  belongs_to :reopened_by, class_name: "User", optional: true

  validates :date, presence: true, uniqueness: { scope: :organization_id }
  validates :status, inclusion: { in: STATUSES }

  scope :settled, -> { where(status: "settled") }

  # The one place that answers "which day is this?".
  def self.day_for(organization, time)
    local = time.in_time_zone(Time.zone)
    return local.to_date if organization.settlement_day_mode == "calendar"

    local.hour < organization.settlement_day_starts_at.to_i ? local.to_date - 1 : local.to_date
  end

  # The span of times that belong to a day.
  def self.window(organization, date)
    if organization.settlement_day_mode == "calendar"
      date.in_time_zone.beginning_of_day..date.in_time_zone.end_of_day
    else
      start = date.in_time_zone.change(hour: organization.settlement_day_starts_at.to_i)
      start...(start + 1.day)
    end
  end

  # A day can be settled once it's over.
  def self.ended?(organization, date, now: Time.current)
    now >= window(organization, date).end
  end

  def settled? = status == "settled"
  def open? = status == "open"

  def settle!(by:)
    update!(status: "settled", settled_at: Time.current, settled_by: by)
  end

  def reopen!(by:, reason:)
    update!(status: "open", reopened_at: Time.current, reopened_by: by, reopen_reason: reason.to_s.strip.presence)
  end

  # Door cash, counted at close.
  def counted_cents = door_cash["counted_cents"]&.to_i
  def float_kept_cents = door_cash["float_kept_cents"].to_i
  def door_cash_note = door_cash["note"].to_s
  def door_cash_counted? = !counted_cents.nil?
  def register_checked? = register_checked_at.present?
  def tips_checked? = tips_checked_at.present?

  # Tips handed over in cash at close come out of the door cash.
  def cash_tips_cents = tip_shares.select(&:cash?).sum(&:amount_cents)
  def payout_tips_cents = tip_shares.select(&:payout?).sum(&:amount_cents)
end

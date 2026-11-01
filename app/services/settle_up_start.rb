# frozen_string_literal: true

# Where Settle up starts for an organization (Tim, 2026-11-01). Without it,
# the day 1.3 ships every organization would open the Money hub to every
# show day it ever had, all "to settle". Days before the start are history:
# never listed, never counted, still open to read, never changed here.
#
# convert! is the one-time switch the 1.3 deploy runs (from the migration
# that adds the column): the start goes to the first of the current month,
# and days since then whose shows were already confirmed in Financials, with
# nothing else in them, count as settled, so an organization that was caught
# up stays caught up. Those days post nothing: settling a show-only day has
# nothing to post (door cash and registers are what SettlementPoster posts,
# and neither existed before 1.3).
class SettleUpStart
  NOTE = "Confirmed in Financials before Settle up started."

  def self.convert_all!(starts_on: Date.current.beginning_of_month)
    Organization.where(settle_up_starts_on: nil).find_each { |org| convert!(org, starts_on: starts_on) }
  end

  def self.convert!(organization, starts_on: Date.current.beginning_of_month)
    organization.update_columns(settle_up_starts_on: starts_on)
    settled = 0
    SettleUp.to_settle(organization).each do |day|
      next unless day.shows.any? && day.shows.all?(&:confirmed?) && !day.door_cash.any? && day.registers.empty?

      SettlementDay.create!(organization: organization, date: day.date, status: "settled", settled_at: Time.current, notes: NOTE)
      settled += 1
    end
    settled
  end
end

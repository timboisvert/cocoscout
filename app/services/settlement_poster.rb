# frozen_string_literal: true

# What settling a day puts on the books, in one entry (kind "settlement",
# plan §9.2): today, the door cash over or short (a short is a cost, an over
# is other income; the cash itself is already counted sale by sale). The
# shows' own money posts from their financials as it always has. Reopening
# withdraws the entry; settling again restates it, dated the original day.
class SettlementPoster
  def self.post!(record)
    organization = record.organization
    day = SettleUp.day(organization, record.date)
    diff = day.door_cash.over_short_cents.to_i
    lines = if diff.negative?
      [ { account: :other_expenses, amount_cents: -diff, memo: "Door cash short" }, { account: :door_cash, amount_cents: diff } ]
    elsif diff.positive?
      [ { account: :door_cash, amount_cents: diff }, { account: :other_income, amount_cents: -diff, memo: "Door cash over" } ]
    else
      []
    end
    LedgerPosting.post!(organization: organization, source: record, kind: "settlement", entry_date: record.date, cash_date: record.date,
                        memo: "Settled #{record.date.strftime('%b %-d, %Y')}", lines: lines)
  rescue StandardError => e
    raise if Rails.env.test?

    Rails.logger.error("[SettlementPoster] day #{record.id}: #{e.class}: #{e.message}")
  end

  def self.unpost!(record)
    LedgerPosting.unpost!(source: record, kind: "settlement")
  end
end

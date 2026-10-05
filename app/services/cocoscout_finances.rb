# frozen_string_literal: true

# CocoScout's own money for a period, for superadmin Finances: what it earned
# by kind, what it spent by kind, what moved to and from its bank, day by
# day, and who paid it. Read only from CocoScout's ledger
# (CocoScoutLedgerEntry), never from the theaters' money.
class CocoScoutFinances
  PERIODS = {
    "this_month" => "This month", "last_month" => "Last month", "last_30_days" => "Last 30 days",
    "this_year" => "This year", "all_time" => "All time"
  }.freeze

  attr_reader :period

  def initialize(period = "this_month", now: Time.current)
    @period = PERIODS.key?(period) ? period : "this_month"
    @now = now
  end

  def range
    @range ||= case period
    when "last_month" then (@now - 1.month).beginning_of_month..(@now - 1.month).end_of_month
    when "last_30_days" then (@now - 30.days)..@now
    when "this_year" then @now.beginning_of_year..@now
    when "all_time" then nil
    else @now.beginning_of_month..@now
    end
  end

  def entries
    scope = CocoScoutLedgerEntry.all
    range ? scope.where(occurred_at: range) : scope
  end

  def by_type(group)
    sums = entries.where(entry_type: CocoScoutLedgerEntry.types_in(group)).group(:entry_type).sum(:amount_cents)
    CocoScoutLedgerEntry.types_in(group).filter_map { |type| [ type, sums[type] ] if sums[type].to_i.nonzero? }
  end

  def income_cents = by_type(:income).sum { |_, cents| cents }
  def costs_cents = by_type(:cost).sum { |_, cents| cents }
  def net_cents = income_cents + costs_cents

  # Net (income less costs) per day, in dollars, for the line chart.
  def daily_net
    types = CocoScoutLedgerEntry.types_in(:income) + CocoScoutLedgerEntry.types_in(:cost)
    zone = Time.zone.tzinfo.name
    from = range&.first || entries.minimum(:occurred_at) || @now
    sums = entries.where(entry_type: types)
                  .group(Arel.sql("DATE(occurred_at AT TIME ZONE 'UTC' AT TIME ZONE #{ActiveRecord::Base.connection.quote(zone)})"))
                  .sum(:amount_cents)
    (from.to_date..(range&.last || @now).to_date).to_h { |day| [ day.iso8601, (sums[day].to_i / 100.0).round(2) ] }
  end

  # Who paid CocoScout in the period, most first.
  def by_organization
    income = entries.where(entry_type: CocoScoutLedgerEntry.types_in(:income)).where.not(organization_id: nil)
                    .group(:organization_id).sum(:amount_cents)
    orgs = Organization.where(id: income.keys).index_by(&:id)
    income.sort_by { |_, cents| -cents }.map { |id, cents| [ orgs[id], cents ] }.select(&:first)
  end
end

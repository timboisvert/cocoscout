# frozen_string_literal: true

# CocoScout's own money for a period, for superadmin Finances: what it earned
# and spent, stream by stream and month by month, what moved to and from its
# bank, and who paid it. Read only from CocoScout's ledger
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

  # Profit and loss for the period, one stream at a time, so each stream's
  # earnings sit beside what Stripe charged to bring them in. Every income
  # and cost entry lands in exactly one stream, so the streams' nets add up
  # to #net_cents.
  #
  #   [{ key:, name:, lines: [[label, cents], ...], net_cents: }, ...]
  def streams
    @streams ||= begin
      income = entries.where(entry_type: CocoScoutLedgerEntry.types_in(:income)).group(:entry_type).sum(:amount_cents)
      processing = processing_cost_by_stream
      tickets = income["ticket_fee"].to_i / TicketPricing::PLATFORM_FEE_CENTS
      list = [
        [ :tickets, "Tickets", [
          [ "50¢ ticket fees#{" (#{ActiveSupport::NumberHelper.number_to_delimited(tickets)} #{'ticket'.pluralize(tickets)})" if tickets.positive?}", income["ticket_fee"] ],
          [ "Card processing buyers paid us", income["ticket_processing"] ],
          [ "Stripe's card processing on tickets", processing[:tickets] ],
          [ "Fees given back on refunds", income["ticket_refund"] ]
        ] ],
        [ :courses, "Courses", [
          [ "Our share of course payments", income["course_fee"] ],
          [ "Stripe's card processing on courses", processing[:courses] ],
          [ "Given back on refunds", income["course_refund"] ]
        ] ],
        [ :contracts, "Contract payments", [
          [ "Card processing passed on to organizations", income["contract_processing"] ],
          [ "Stripe's card processing on them", processing[:contracts] ]
        ] ],
        [ :pro, "Pro plans", [
          [ "Pro bills paid", income["subscription"] ],
          [ "Stripe's processing on those bills", processing[:pro] ]
        ] ],
        [ :usage, "Usage ($3 a performer, $5 a staff member)", [
          [ "Usage bills paid", income["usage"] ],
          [ "Stripe's processing on those bills", processing[:usage] ]
        ] ],
        [ :running, "Running CocoScout", stripe_fee_lines + [
          [ "Bank-debit fees on payout runs and top-ups (we absorb them)", entries.where(entry_type: "funding_cost").sum(:amount_cents) ],
          [ "Stripe's processing on other charges", processing[:running] ],
          [ "Other Stripe income", income["other_income"] ]
        ] ]
      ]
      list.filter_map do |key, name, lines|
        lines = lines.map { |label, cents| [ label, cents.to_i ] }.reject { |_, cents| cents.zero? }
        { key: key, name: name, lines: lines, net_cents: lines.sum(&:last) } if lines.any?
      end
    end
  end

  # Earned, spent and kept, month by month, newest first, for the last
  # twelve months (the current one so far).
  def self.monthly(months: 12, now: Time.current)
    from = (now - (months - 1).months).beginning_of_month
    zone = ActiveRecord::Base.connection.quote(Time.zone.tzinfo.name)
    month = Arel.sql("DATE_TRUNC('month', occurred_at AT TIME ZONE 'UTC' AT TIME ZONE #{zone})::date")
    income = CocoScoutLedgerEntry.where(occurred_at: from..now, entry_type: CocoScoutLedgerEntry.types_in(:income)).group(month).sum(:amount_cents)
    costs = CocoScoutLedgerEntry.where(occurred_at: from..now, entry_type: CocoScoutLedgerEntry.types_in(:cost)).group(month).sum(:amount_cents)
    fees = CocoScoutLedgerEntry.where(occurred_at: from..now, entry_type: "ticket_fee").group(month).sum(:amount_cents)
    (0...months).map do |back|
      day = (now - back.months).to_date.beginning_of_month
      earned = income[day].to_i
      spent = -costs[day].to_i
      { month: day, earned_cents: earned, spent_cents: spent, kept_cents: earned - spent,
        tickets: fees[day].to_i / TicketPricing::PLATFORM_FEE_CENTS, partial: back.zero? }
    end
  end

  # The current month, only a few days in: Stripe's monthly fees for the
  # month before land on the first days, ahead of most of this month's
  # earnings, so the month can look like a loss when it isn't one yet.
  def early_in_month?
    period == "this_month" && @now.day <= 7
  end

  # Who paid CocoScout in the period, most first.
  def by_organization
    income = entries.where(entry_type: CocoScoutLedgerEntry.types_in(:income)).where.not(organization_id: nil)
                    .group(:organization_id).sum(:amount_cents)
    orgs = Organization.where(id: income.keys).index_by(&:id)
    income.sort_by { |_, cents| -cents }.map { |id, cents| [ orgs[id], cents ] }.select(&:first)
  end

  private

  # Stripe's card processing, by the stream that paid it: a ticket order's,
  # a course's, a contract payment's; on a bill, the bill's kind.
  def processing_cost_by_stream
    scope = entries.where(entry_type: "processing_cost")
    direct = scope.where.not(source_type: "StripeBalanceTransaction").group(:source_type).sum(:amount_cents)
    bills = scope.where(source_type: "StripeBalanceTransaction")
                 .joins("JOIN stripe_balance_transactions sbt ON sbt.id = cocoscout_ledger_entries.source_id")
                 .joins("LEFT JOIN billing_invoices bi ON sbt.matched_type = 'BillingInvoice' AND bi.id = sbt.matched_id")
                 .group("bi.kind").sum(:amount_cents)
    stream_of = { "TicketOrder" => :tickets, "TicketPassHolding" => :tickets, "CourseRegistration" => :courses, "ContractPayment" => :contracts }
    totals = Hash.new(0)
    direct.each { |type, cents| totals[stream_of.fetch(type, :running)] += cents }
    bills.each { |kind, cents| totals[kind.nil? ? :running : (kind == "usage" ? :usage : :pro)] += cents }
    totals
  end

  # Stripe's own fees, by what Stripe calls them, with its date ranges
  # dropped so a month's "Connect: Active Accounts" adds up as one line.
  def stripe_fee_lines
    sums = entries.where(entry_type: "stripe_fee").group(:description).sum(:amount_cents)
    named = Hash.new(0)
    sums.each do |description, cents|
      name = description.to_s.gsub(/\s*\([^)]*\)/, "").squish.presence || "Stripe fee"
      named[name.start_with?("Stripe") ? name : "Stripe: #{name}"] += cents
    end
    named.sort_by { |_, cents| cents }.to_a
  end
end

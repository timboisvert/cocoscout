# frozen_string_literal: true

# Whether waiting a day or two would let the CocoScout balance pay more of a
# payout run that's waiting on it (Tim, 2026-11-22: "understand if waiting a
# day or two would be wise"). Only money already sold counts: each ticket
# sale becomes spendable two days after it was paid, once its show has
# happened (released at 4am Chicago the next day; TicketMoneyReleaseJob),
# less the sales tax set aside then; course and contract money two days after
# it came in. Nothing sold later, and no refund, is guessed at.
#
#   PayoutBalanceForecast.rows(batch) => [Row(date:, available_cents:, covered:, bank_cents:), ...]
#
# One row for today, one for the day the bank debit is scheduled, one for
# each day between where what the bank would pay changes, and on past the
# scheduled debit to the first
# day the balance covers everyone (a week at most), so a manager can see
# whether moving the debit later would save it.
#
# For a draft, bank_day: when the bank would pay (bank_due_at_for), and
# skip: the items Pay now pays from the balance at once.
class PayoutBalanceForecast
  Row = Data.define(:date, :available_cents, :covered, :bank_cents)
  RELEASE_ZONE = "America/Chicago"
  RELEASE_HOUR = 4
  HORIZON_DAYS = 7

  def self.rows(batch, now: Time.current, bank_day: nil, skip: [])
    org = batch.organization
    zone = ActiveSupport::TimeZone[org.time_zone] || Time.zone
    today = now.in_time_zone(zone).to_date
    bank_day ||= (batch.bank_due_at || now).in_time_zone(zone).to_date

    credits = incoming(org, now: now)
    skipped = skip.sum(&:amount_cents)
    skip_ids = skip.map(&:id)
    waiting = batch.items.includes(:payee, :payout_contributions).to_a
                   .select { |item| item.status == "pending" && item.amount_cents.to_i.positive? && !skip_ids.include?(item.id) }
    payable = PayoutPayOrder.sort(batch, waiting.select(&:payable_now?))
    rest = PayoutBatchService.rest_cents(batch) - skipped
    held = batch.held_cents
    credit = PayoutFundingCredit.available_cents(org)
    available_now = CocoScoutBalance.available_cents(org) - skipped

    rows = []
    (today..(today + HORIZON_DAYS)).each do |date|
      day_end = zone.local(date.year, date.month, date.day).end_of_day
      available = available_now + credits.sum { |at, cents| at <= day_end ? cents : 0 }
      rows << Row.new(date: date, available_cents: available, covered: covered(payable, available),
                      bank_cents: [ rest - held - credit - available, 0 ].max)
      break if date >= bank_day && rows.last.bank_cents.zero?
    end
    # Days that change nothing drop out, so past the scheduled debit a row shows
    # only when waiting longer would change what the bank pays.
    rows.each_with_index.select { |row, i| i.zero? || row.date == bank_day || row.bank_cents != rows[i - 1].bank_cents }.map(&:first)
  end

  # The one thing worth knowing, from the rows: { text:, wait_until: Date or
  # nil }. wait_until is a day after the scheduled bank debit that would save
  # the whole debit (the run page offers to move the debit to that day).
  def self.advice(rows, bank_day:)
    return nil if rows.empty?

    day = ->(date) { date.strftime("%A, %B %-d") }
    money = ->(cents) { ActiveSupport::NumberHelper.number_to_currency(cents / 100.0) }
    today = rows.first
    bank = rows.reverse.find { |row| row.date <= bank_day } || today
    covered = rows.find { |row| row.bank_cents.zero? }

    if covered && covered.date <= bank_day
      when_words = covered == today ? "today" : "by #{day.call(covered.date)}"
      { text: "Ticket money already sold should cover everyone left #{when_words}, so your bank shouldn't have to pay anything.", wait_until: nil }
    elsif covered
      { text: "If you wait until #{day.call(covered.date)}, your bank shouldn't have to pay anything.", wait_until: covered.date }
    elsif bank.bank_cents < today.bank_cents
      { text: "The bank debit is scheduled for #{day.call(bank_day)}. By then it should be #{money.call(bank.bank_cents)} instead of #{money.call(today.bank_cents)}.", wait_until: nil }
    else
      { text: "No more ticket money clears before the bank debit on #{day.call(bank_day)}, so waiting won't make it smaller.", wait_until: nil }
    end
  end

  # How many of these (in pay order) the balance covers, whole payments only.
  def self.covered(items, budget)
    items.count do |item|
      next false if item.amount_cents > budget

      budget -= item.amount_cents
      true
    end
  end

  # [[Time it becomes spendable, cents], ...] for money already in the
  # ledger that isn't spendable yet.
  def self.incoming(organization, now: Time.current)
    ticket_money(organization, now: now) + other_money(organization, now: now)
  end

  def self.ticket_money(organization, now:)
    settle = TicketBalance::SETTLE_AFTER
    sql = <<~SQL.squish
      SELECT e.amount_cents, o.paid_at, o.tax_cents, o.org_net_cents, o.money_path, l.released_at, s.date_and_time
      FROM org_cash_entries e
      #{TicketBalance::ORDER_OF_ENTRY}
      JOIN ticket_listings l ON l.id = o.ticket_listing_id
      JOIN shows s ON s.id = l.show_id
      WHERE e.organization_id = :organization_id AND e.entry_type IN (:types)
        AND (l.released_at IS NULL OR o.paid_at > :cutoff)
        AND (l.released_at IS NOT NULL OR (l.status <> 'canceled' AND NOT s.canceled))
    SQL
    types = TicketBalance::ENTRY_TYPES - %w[pass_sale pass_refund]
    rows = OrgCashEntry.connection.select_rows(
      OrgCashEntry.sanitize_sql([ sql, { organization_id: organization.id, types: types, cutoff: now - settle } ])
    )
    tax_aside = SalesTaxSetAside.on?(organization)
    release_zone = ActiveSupport::TimeZone[RELEASE_ZONE]
    rows.map do |amount, paid_at, tax, net, path, released_at, show_at|
      amount = amount.to_i
      paid_at = paid_at.to_time
      ready = paid_at + settle
      unless released_at
        show_day = show_at.to_time.in_time_zone(release_zone).to_date
        ready = [ ready, release_zone.local(show_day.year, show_day.month, show_day.day, RELEASE_HOUR) + 1.day ].max
      end
      # The sale's sales tax is set aside the moment it becomes spendable.
      aside = tax_aside && path == "cocoscout" && net.to_i.positive? ? (amount * tax.to_i / net.to_f).round : 0
      [ ready, amount - aside ]
    end
  end

  def self.other_money(organization, now:)
    OrgCashEntry.where(organization: organization, entry_type: CocoScoutBalance::OTHER_CREDITS)
                .where("occurred_at > ?", now - TicketBalance::SETTLE_AFTER)
                .pluck(:occurred_at, :amount_cents)
                .map { |at, cents| [ at + TicketBalance::SETTLE_AFTER, cents ] }
  end

  private_class_method :covered, :ticket_money, :other_money
end

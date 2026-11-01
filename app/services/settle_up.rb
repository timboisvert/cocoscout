# frozen_string_literal: true

# The pieces of a day, read live (Books V1.3, plan §9.2): each revenue show
# that happened that day with its Show Financials, and the door cash. A day
# appears when it had money in it; its state is the SettlementDay row, if
# one was made. Days are cut by SettlementDay.day_for.
#
#   SettleUp.day(organization, date)        # one Day, pieces and all
#   SettleUp.days(organization, range)      # the Days in a span, newest first
#   SettleUp.to_settle(organization)        # days over and not yet settled
class SettleUp
  ShowPiece = Data.define(:show, :financials, :listing, :ticket_lines, :outside_sources, :products_cents, :other_revenue_cents, :expenses_cents, :flat_fee_cents) do
    def confirmed? = financials&.data_confirmed? == true
    def tickets_count = ticket_lines.sum { |l| l[:count] }
    def tickets_cents = ticket_lines.sum { |l| l[:cents] }
    def in_cents = tickets_cents + products_cents + other_revenue_cents + flat_fee_cents
    def state = confirmed? ? :ok : (financials&.has_data? ? :wait : :miss)
  end

  DoorCash = Data.define(:expected_cents, :cash_orders_count, :record) do
    def counted? = record&.door_cash_counted? == true
    def counted_cents = record&.counted_cents
    def over_short_cents = counted? ? counted_cents - expected_cents : nil
    def to_deposit_cents = counted? ? counted_cents - record.float_kept_cents : nil
    def state = counted? ? :ok : :miss
    def any? = cash_orders_count.positive? || counted?
  end

  # Someone who worked the day, for splitting tips: from Staffing's shifts
  # and hours. hours is what they logged, else what they were scheduled.
  Worker = Data.define(:person, :hours, :staff_member)

  # The day's tips (plan §9.3): the register's total, how it's split, each
  # share, and who was there. Nothing is split until someone checks it.
  Tips = Data.define(:cents, :record, :shares, :workers) do
    def any? = cents.positive?
    def checked? = record&.tips_checked? == true
    def state = checked? ? :ok : :wait
    def split = record&.tips_split.presence || "even"
    def assigned_cents = shares.sum(&:amount_cents)
    def unassigned_cents = cents - assigned_cents
    def share_for(person) = shares.find { |sh| sh.person_id == person.id }
  end

  Day = Data.define(:organization, :date, :record, :shows, :door_cash, :registers, :tips) do
    def settled? = record&.settled? == true
    def status = settled? ? "settled" : "open"
    def ended? = SettlementDay.ended?(organization, date)
    def registers_state = record&.register_checked? ? :ok : :wait
    def register_label = registers.size == 1 ? "Bar, #{registers.first.location_name}" : "Registers"
    def pieces
      shows.map { |s| [ s.show.display_name, s.state ] } +
        (door_cash.any? ? [ [ "Door cash", door_cash.state ] ] : []) +
        (registers.any? ? [ [ register_label, registers_state ] ] : []) +
        (tips.any? ? [ [ "Tips", tips.state ] ] : [])
    end
    def checked_count = pieces.count { |_, state| state == :ok }
    def all_checked? = pieces.any? && pieces.all? { |_, state| state == :ok }
    def register_sales_cents = registers.sum { |r| r.gross_cents - r.refunds_cents }
    def in_cents = shows.sum(&:in_cents) + register_sales_cents
    def out_cents = shows.sum(&:expenses_cents) + registers.sum(&:fees_cents)
    def any? = shows.any? || door_cash.any? || registers.any?
    def to_settle? = any? && !settled? && ended? && !before_start?
    # Before the organization's Settle up start date: history, read only.
    def before_start? = organization.settle_up_starts_on.present? && date < organization.settle_up_starts_on
    def param = date.iso8601
  end

  def self.day(organization, date)
    build(organization, date, shows_on(organization, date), SettlementDay.find_by(organization: organization, date: date))
  end

  # Every day in the span that had a show or a register day, newest first.
  def self.days(organization, range)
    shows = revenue_shows(organization).where(date_and_time: range.begin.in_time_zone.beginning_of_day..(range.end.in_time_zone.end_of_day + 1.day)).to_a
    records = SettlementDay.where(organization: organization, date: range).index_by(&:date)
    by_date = shows.group_by { |s| SettlementDay.day_for(organization, s.date_and_time) }.select { |d, _| range.cover?(d) }
    register_dates = register_days(organization).where(business_date: range).distinct.pluck(:business_date)
    dates = (by_date.keys + records.keys + register_dates).uniq.sort.reverse
    dates.map { |date| build(organization, date, by_date.fetch(date, []), records[date]) }
  end

  # Days that are over, had money in them, and nobody has settled, from the
  # organization's Settle up start date on (SettleUpStart): earlier days are
  # history.
  def self.to_settle(organization, as_of: Time.current)
    starts = organization.settle_up_starts_on
    shows = revenue_shows(organization).where("date_and_time <= ?", as_of)
    shows = shows.where("date_and_time >= ?", starts.in_time_zone.beginning_of_day - 1.day) if starts
    shows = shows.to_a
    settled = SettlementDay.where(organization: organization).settled.pluck(:date).to_set
    by_date = shows.group_by { |s| SettlementDay.day_for(organization, s.date_and_time) }
    register_days(organization).where("business_date <= ?", as_of.to_date).distinct.pluck(:business_date).each { |d| by_date[d] ||= [] }
    by_date.reject { |date, _| settled.include?(date) || (starts && date < starts) || !SettlementDay.ended?(organization, date, now: as_of) }
           .sort_by { |date, _| date }
           .map { |date, day_shows| build(organization, date, day_shows, nil) }
  end

  # Register days from connected integrations, with something in them.
  def self.register_days(organization)
    RegisterDay.counted.where(organization_id: organization.id).where("orders_count > 0 OR gross_cents > 0 OR refunds_cents > 0")
  end

  def self.shows_on(organization, date)
    window = SettlementDay.window(organization, date)
    revenue_shows(organization).where(date_and_time: window).to_a
  end

  # Revenue shows that aren't canceled and aren't course sessions: the same
  # shows that used to be listed as needing financials.
  def self.revenue_shows(organization)
    Show.joins(:production).where(productions: { organization_id: organization.id })
        .where(event_type: EventTypes.revenue_event_types, canceled: false)
        .where.not(production_id: Production.courses.select(:id))
        .includes(:production, :ticket_listing, show_financials: %i[expense_items ticket_sales_lines])
        .order(:date_and_time)
  end

  def self.build(organization, date, shows, record)
    pieces = shows.sort_by(&:date_and_time).map { |show| show_piece(organization, show) }
    registers = register_days(organization).on(date).includes(:integration, :location).order(:external_location_id).to_a
    Day.new(organization: organization, date: date, record: record, shows: pieces, door_cash: door_cash(organization, date, shows, record),
            registers: registers, tips: tips(organization, date, registers, record))
  end

  def self.tips(organization, date, registers, record)
    cents = registers.select { |r| r.integration.brings?("tips") }.sum(&:tips_cents)
    shares = record ? record.tip_shares.includes(:person).to_a : []
    Tips.new(cents: cents, record: record, shares: shares, workers: (cents.positive? ? workers(organization, date, shares) : []))
  end

  # Who worked the day: Staffing's shift assignments and logged hours in the
  # day's window, plus anyone already given a share.
  def self.workers(organization, date, shares)
    window = SettlementDay.window(organization, date)
    hours = Hash.new(0.0)
    people = {}
    organization.staff_time_entries.where(started_at: window).includes(:person).each do |entry|
      people[entry.person_id] = entry.person
      hours[entry.person_id] += entry.hours.to_f
    end
    organization.shifts.where(starts_at: window).includes(shift_assignments: :person).each do |shift|
      shift.shift_assignments.select(&:active?).each do |assignment|
        people[assignment.person_id] ||= assignment.person
        hours[assignment.person_id] += shift.scheduled_hours unless hours.key?(assignment.person_id)
      end
    end
    shares.each { |sh| people[sh.person_id] ||= sh.person }
    members = organization.organization_staff_members.where(person_id: people.keys).index_by(&:person_id)
    people.values.sort_by(&:name).map { |person| Worker.new(person: person, hours: hours[person.id].round(2), staff_member: members[person.id]) }
  end

  def self.show_piece(organization, show)
    financials = show.show_financials
    listing = show.ticket_listing
    sources = organization.ticket_sources.index_by(&:id)
    lines = (financials&.ticket_sales_lines || []).map do |line|
      source = sources[line.ticket_source_id]
      { label: source&.name || "Tickets", built_in: source&.built_in? == true, count: line.tickets_sold.to_i, cents: (line.amount.to_f * 100).round }
    end
    if lines.empty? && financials&.ticket_revenue.to_f.positive?
      lines << { label: "Tickets", built_in: false, count: financials.ticket_count.to_i, cents: (financials.ticket_revenue.to_f * 100).round }
    end
    outside = listing ? sources.values.select { |s| !s.built_in? && s.archived_at.nil? } : []
    products = financials ? financials.normalized_other_revenue_details.select { |i| i.is_a?(Hash) && i["description"] == TicketSalesSync::PRODUCTS_LABEL }.sum { |i| (i["amount"].to_f * 100).round } : 0
    other = financials ? financials.normalized_other_revenue_details.select { |i| i.is_a?(Hash) && i["description"] != TicketSalesSync::PRODUCTS_LABEL }.sum { |i| (i["amount"].to_f * 100).round } : 0
    other += (financials.other_revenue.to_f * 100).round if financials && financials.normalized_other_revenue_details.empty?
    expenses = financials ? (financials.calculated_expenses * 100).round : 0
    fee = financials&.flat_fee? ? (financials.flat_fee.to_f * 100).round : 0
    ShowPiece.new(show: show, financials: financials, listing: listing, ticket_lines: lines, outside_sources: outside,
                  products_cents: products, other_revenue_cents: other, expenses_cents: expenses, flat_fee_cents: fee)
  end

  # Cash taken at the door for the day's shows (tickets and products paid
  # in cash), which should be in the box at close.
  def self.door_cash(organization, date, shows, record)
    listing_ids = shows.filter_map { |s| s.ticket_listing&.id }
    orders = listing_ids.any? ? TicketOrder.where(ticket_listing_id: listing_ids, money_path: "cash", status: TicketOrder::WAS_PAID) : TicketOrder.none
    DoorCash.new(expected_cents: orders.sum(:total_cents) - orders.sum(:refunded_cents), cash_orders_count: orders.count, record: record)
  end
end

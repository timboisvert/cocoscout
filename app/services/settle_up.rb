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
  # A value worked out the first time it's asked for: the lists of days never
  # ask a show who it pays, the day's page does.
  class Cell
    def initialize(&block) = @block = block
    def value = (@value ||= @block.call)
  end

  ShowPiece = Data.define(:show, :financials, :listing, :ticket_lines, :outside_sources, :products_cents, :other_revenue_cents, :expenses_cents, :flat_fee_cents, :pay_cell) do
    def confirmed? = financials&.data_confirmed? == true
    def tickets_count = ticket_lines.sum { |l| l[:count] }
    def tickets_cents = ticket_lines.sum { |l| l[:cents] }
    def in_cents = tickets_cents + products_cents + other_revenue_cents + flat_fee_cents
    # A show marked as having no revenue: nothing to count, nobody paid
    # from it, still confirmed like any other.
    def non_revenue? = financials&.non_revenue_override? == true
    def state = confirmed? ? :ok : (financials&.has_data? || non_revenue? ? :wait : :miss)
    # Who gets paid from this show (Pay), worked out when first asked.
    def pay = pay_cell.value
    # Why the show can't be confirmed yet, if it can't: the pay side has a
    # question open (no calculation, act counts to enter).
    def hold_reason = confirmed? ? nil : pay.hold_reason
  end

  # One person's line in "Who gets paid" from a show: the calculated line
  # (nil before the money is confirmed, when the row is a preview), what
  # they get, and where it stands.
  #   stage  :preview   worked out, not saved yet (the money isn't confirmed)
  #          :run       on the payout run when the day settles
  #          :hold      held back for now
  #          :paid      paid another way, or by a run that went out
  #          :in_draft  on the open run (the day settled), still a draft
  #          :in_flight on a run that's funding or sending
  PayRow = Data.define(:line, :payee, :name, :cents, :stage, :note)

  # Who gets paid from a show (Tim, 2026-11-04: paying people is part of
  # settling up). kind is :performers (the production's payout calculation
  # pays the people cast), :contract (the show settles on a contract's
  # payments) or :none (nobody is paid from this show).
  # calc says where the payout calculation stands (Tim, 2026-11-04: a
  # calculate step first, and a word when the numbers moved under it):
  #   :none         no calculation to run (a contract, nobody paid, no scheme)
  #   :no_cast      nobody is cast, so there's nobody to pay
  #   :needs_numbers the money isn't entered yet, so it can't be worked out
  #   :uncalculated it can be worked out from the numbers as they stand
  #   :stale        worked out, but the numbers changed since; work it out again
  #   :locked       worked out and the numbers changed since, but lines are
  #                 paid or on a run, so it stays as it is
  #   :current      worked out from these numbers
  # preview_cents / preview_count: what the numbers as they stand would pay
  # (an :uncalculated or :stale show), nil otherwise.
  Pay = Data.define(:kind, :show, :show_payout, :scheme, :rows, :payments, :hold_reason, :calc, :preview_cents, :preview_count) do
    def performers? = kind == :performers
    def contract? = kind == :contract
    def none? = kind == :none
    def held? = hold_reason.present?
    def calculated? = performers? && show_payout&.calculated_at.present? && rows.any?
    def can_calculate? = calc.in?(%i[uncalculated stale])
    def total_cents = performers? ? rows.sum(&:cents) : payments.sum { |p| (p.amount.to_d * 100).round }
    # What settling the day puts on the run, and for how many people.
    def to_run_rows = rows.select { |r| r.stage == :run }
    def to_run_cents = performers? ? to_run_rows.sum(&:cents) : payments.select { |p| SettlementPayer.stageable?(p) }.sum { |p| (p.amount.to_d * 100).round }
    def to_run_count = performers? ? to_run_rows.size : payments.count { |p| SettlementPayer.stageable?(p) }
    def count_by_stage = rows.group_by(&:stage).transform_values(&:size)
  end

  Check = Data.define(:key, :name, :short, :state, :hold_reason) do
    def ok? = state == :ok
    def held? = !ok? && hold_reason.present?
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
  # and hours, each span in the role it was worked (TipSplit::Span). hours is
  # what they logged, else what they were scheduled.
  Worker = Data.define(:person, :staff_member, :spans) do
    def hours = spans.sum(&:hours).round(2)
  end

  # The day's tips (plan §9.3): the register's total, how it's split, each
  # share, and who was there. Nothing is split until someone checks it.
  # With the organization's tip rule on and the clock to read (§9.14), the
  # split is worked out from who was on: rows, pool.
  Tips = Data.define(:cents, :record, :shares, :workers, :rule, :by_time, :calculator) do
    def any? = cents.positive?
    def checked? = record&.tips_checked? == true
    def state = checked? ? :ok : :wait
    def split = record&.tips_split.presence_in(%w[even hours typed]) || "even"
    def assigned_cents = shares.sum(&:amount_cents)
    def unassigned_cents = cents - assigned_cents
    def share_for(person) = shares.find { |sh| sh.person_id == person.id }
    # With the rule on, only people in a role that shares are listed anywhere
    # (Tim, 2026-11-03: not the door, not the booth). A saved share in any
    # other role, or in none, doesn't put someone on the list.
    def sharers
      return workers unless rule&.enabled?

      calculator.sharers
    end
    def by_rule? = calculator.applies?
    def rows = calculator.rows
    # The stretches of time with nobody on the bar, each a question for the
    # manager; the day's register can't be checked while one is unanswered.
    def stretches = by_rule? ? calculator.stretches : []
    def periods = by_rule? ? calculator.periods : []
    def shared? = by_rule? && calculator.shared?
    def unresolved = by_rule? ? calculator.unresolved : []
    # What stays with the house: by the rule, the stretches it keeps; by
    # hand, whatever the shares don't add up to.
    def house_cents = by_rule? ? calculator.house_cents : [ unassigned_cents, 0 ].max
    def given_cents = cents - house_cents

    # The by-hand rows: each sharer with the saved share, else the
    # suggestion for the chosen split (evenly, by hours, or nothing yet).
    def hand_rows
      workers = sharers
      total_hours = workers.sum(&:hours)
      workers.map do |worker|
        share = share_for(worker.person)
        suggested = case split
        when "hours" then total_hours.positive? ? (cents * worker.hours / total_hours).round : 0
        when "typed" then 0
        else workers.any? ? (cents / workers.size.to_f).round : 0
        end
        { worker: worker, share: share, cents: (share ? share.amount_cents : suggested), method: (share&.method || (worker.staff_member ? "payout" : "cash")) }
      end
    end
  end

  Day = Data.define(:organization, :date, :record, :shows, :door_cash, :registers, :tips) do
    def settled? = record&.settled? == true
    def status = settled? ? "settled" : "open"
    def ended? = SettlementDay.ended?(organization, date)
    def registers_state = record&.register_checked? ? :ok : :wait
    def register_label = registers.size == 1 ? "Bar, #{registers.first.location_name}" : "Registers"
    # Every piece to confirm, in page order, with why it can't be yet when it
    # can't: the rail at the bottom draws one dot per check.
    def checks
      shows.map { |s| Check.new(key: "show-#{s.show.id}", name: s.show.display_name, short: SettleUp.short_name(s.show), state: s.state, hold_reason: s.hold_reason) } +
        (door_cash.any? ? [ Check.new(key: "door-cash", name: "Door cash", short: "Door cash", state: door_cash.state, hold_reason: nil) ] : []) +
        (registers.any? ? [ Check.new(key: "register", name: register_label, short: (registers.size == 1 ? "Bar" : "Registers"), state: registers_state,
                                      hold_reason: (tips.unresolved.any? ? "Say who gets the tips rung up with nobody on the bar first" : nil)) ] : [])
    end
    def pieces = checks.map { |c| [ c.name, c.state ] }
    def checked_count = checks.count(&:ok?)
    def all_checked? = checks.any? && checks.all?(&:ok?)
    # What settling puts on the payout run: the sum over the shows, and how
    # many people (a person in two shows counts once per show here; the run
    # itself folds them into one line).
    def to_run_cents = shows.sum { |s| s.pay.to_run_cents }
    def to_run_count = shows.sum { |s| s.pay.to_run_count }
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
    registers = registers_by_date(organization, dates)
    cash = door_cash_by_listing(shows)
    dates.map { |date| build(organization, date, by_date.fetch(date, []), records[date], registers: registers.fetch(date, []), cash: cash) }
  end

  # Just the dates in the span that had money in them, for a calendar's dots.
  def self.dates(organization, range)
    shows = revenue_shows(organization).where(date_and_time: range.begin.in_time_zone.beginning_of_day..(range.end.in_time_zone.end_of_day + 1.day)).pluck(:date_and_time)
    dates = shows.map { |t| SettlementDay.day_for(organization, t) }.select { |d| range.cover?(d) }
    dates += SettlementDay.where(organization: organization, date: range).pluck(:date)
    dates += register_days(organization).where(business_date: range).distinct.pluck(:business_date)
    dates.to_set
  end

  # Where each day with money in it stands, for the calendar's dots (Tim,
  # 2026-11-03: not that a day had money, but whether it's done): settled,
  # to settle (over and open), or waiting (not over yet, or history from
  # before the Settle up start date).
  def self.date_states(organization, range)
    settled = SettlementDay.where(organization: organization, date: range).settled.pluck(:date).to_set
    starts = organization.settle_up_starts_on
    dates(organization, range).to_h do |date|
      state = if settled.include?(date) then :settled
      elsif (starts && date < starts) || !SettlementDay.ended?(organization, date) then :waiting
      else :to_settle
      end
      [ date, state ]
    end
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
    open = by_date.reject { |date, _| settled.include?(date) || (starts && date < starts) || !SettlementDay.ended?(organization, date, now: as_of) }
                  .sort_by { |date, _| date }
    registers = registers_by_date(organization, open.map(&:first))
    cash = door_cash_by_listing(open.flat_map(&:last))
    open.map { |date, day_shows| build(organization, date, day_shows, nil, registers: registers.fetch(date, []), cash: cash) }
  end

  # The register days for many dates at once, by date (the Settle up list
  # was asking for each day's on its own, 2026-11-02).
  def self.registers_by_date(organization, dates)
    return {} if dates.empty?

    register_days(organization).where(business_date: dates).includes(:integration, :location).order(:external_location_id).to_a.group_by(&:business_date)
  end

  # Cash at the door by listing, for many days at once: [taken, refunded, orders].
  def self.door_cash_by_listing(shows)
    ids = shows.filter_map { |s| s.ticket_listing&.id }
    return {} if ids.empty?

    TicketOrder.where(ticket_listing_id: ids, money_path: "cash", status: TicketOrder::WAS_PAID).group(:ticket_listing_id)
               .pluck(:ticket_listing_id, Arel.sql("COALESCE(SUM(total_cents), 0)"), Arel.sql("COALESCE(SUM(refunded_cents), 0)"), Arel.sql("COUNT(*)"))
               .to_h { |id, taken, refunded, count| [ id, [ taken.to_i, refunded.to_i, count.to_i ] ] }
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

  # registers and cash: read for many days at once by days / to_settle.
  def self.build(organization, date, shows, record, registers: nil, cash: nil)
    pieces = shows.sort_by(&:date_and_time).map { |show| show_piece(organization, show) }
    registers ||= register_days(organization).on(date).includes(:integration, :location).order(:external_location_id).to_a
    Day.new(organization: organization, date: date, record: record, shows: pieces, door_cash: door_cash(organization, date, shows, record, cash: cash),
            registers: registers, tips: tips(organization, date, registers, record))
  end

  def self.tips(organization, date, registers, record)
    with_tips = registers.select { |r| r.integration.brings?("tips") }
    cents = with_tips.sum(&:tips_cents)
    shares = record ? record.tip_shares.includes(:person).to_a : []
    by_time = with_tips.each_with_object(Hash.new { |h, k| h[k] = { "cents" => 0, "orders" => 0 } }) do |register, merged|
      register.tips_by_time.each { |key, q| merged[key]["cents"] += q["cents"].to_i; merged[key]["orders"] += q["orders"].to_i }
    end
    workers = cents.positive? ? workers(organization, date, shares) : []
    rule = organization.tip_rule
    Tips.new(cents: cents, record: record, shares: shares, workers: workers, rule: rule, by_time: by_time.to_h,
             calculator: TipSplit.new(rule: rule, tips_cents: cents, tips_by_time: by_time.to_h, workers: workers, shares: shares, choices: record&.tips_unstaffed || {}))
  end

  # Who worked the day, and when: a saved share's span when someone set it,
  # else Staffing's logged hours in the day's window, else the scheduled
  # shift; plus anyone already given a share. Each span knows its role.
  def self.workers(organization, date, shares)
    window = SettlementDay.window(organization, date)
    people = {}
    logged = Hash.new { |h, k| h[k] = [] }
    scheduled = Hash.new { |h, k| h[k] = [] }
    organization.staff_time_entries.where(started_at: window).includes(:person, shift_assignment: :shift).each do |entry|
      people[entry.person_id] = entry.person
      logged[entry.person_id] << TipSplit::Span.new(from: entry.started_at, to: entry.ended_at, house_role_id: entry.house_role_id || entry.shift_assignment&.shift&.house_role_id)
    end
    organization.shifts.where(starts_at: window).includes(shift_assignments: :person).each do |shift|
      shift.shift_assignments.select(&:active?).each do |assignment|
        people[assignment.person_id] ||= assignment.person
        scheduled[assignment.person_id] << TipSplit::Span.new(from: shift.starts_at, to: shift.ends_at, house_role_id: shift.house_role_id)
      end
    end
    set_by_hand = {}
    shares.each do |sh|
      people[sh.person_id] ||= sh.person
      set_by_hand[sh.person_id] = [ TipSplit::Span.new(from: sh.worked_from, to: sh.worked_to, house_role_id: sh.house_role_id) ] if sh.worked_from && sh.worked_to
    end
    members = organization.organization_staff_members.where(person_id: people.keys).index_by(&:person_id)
    people.values.sort_by(&:name).map do |person|
      spans = set_by_hand[person.id] || (logged[person.id].presence || scheduled[person.id]).sort_by(&:from)
      Worker.new(person: person, staff_member: members[person.id], spans: spans)
    end
  end

  # What a ticket with no type of its own is called: a show CocoScout
  # doesn't sell has no ticket types here until someone names one.
  PLAIN_TICKET = "General Admission"

  # The ticket types a show CocoScout doesn't sell has numbers for, the
  # plain one first while any line has no type (or there are no lines).
  def self.typed_ticket_types(financials)
    lines = (financials&.ticket_sales_lines || []).reject { |line| line.ticket_source&.built_in? }
    named = lines.filter_map { |line| line.ticket_type.presence }.uniq
    plain = named.empty? || lines.any? { |line| line.ticket_type.blank? }
    ((plain ? [ PLAIN_TICKET ] : []) + named).uniq
  end

  def self.show_piece(organization, show)
    financials = show.show_financials
    listing = show.ticket_listing
    sources = organization.ticket_sources.index_by(&:id)
    # What each other site sold, by ticket type: a show sold here keeps
    # that per type (ticket_outside_sales); a show CocoScout doesn't sell
    # keeps the type on the line itself.
    by_type = Hash.new { |h, k| h[k] = [] }
    listing&.ticket_outside_sales&.includes(:ticket_tier)&.sort_by { |row| [ row.ticket_tier.position.to_i, row.ticket_tier_id ] }&.each do |row|
      by_type[row.ticket_source_id] << [ row.ticket_tier.name, row.tickets_sold.to_i ]
    end
    lines = (financials&.ticket_sales_lines || []).map do |line|
      source = sources[line.ticket_source_id]
      built_in = source&.built_in? == true
      types = if built_in then []
      elsif listing then by_type[line.ticket_source_id]
      else [ [ line.ticket_type.presence || PLAIN_TICKET, line.tickets_sold.to_i ] ]
      end
      { label: source&.name || "Tickets", built_in: built_in, count: line.tickets_sold.to_i, cents: (line.amount.to_f * 100).round, types: types }
    end
    if lines.empty? && financials&.ticket_revenue.to_f.positive?
      lines << { label: "Tickets", built_in: false, count: financials.ticket_count.to_i, cents: (financials.ticket_revenue.to_f * 100).round, types: [] }
    end
    outside = listing ? sources.values.select { |s| !s.built_in? && s.archived_at.nil? } : []
    products = financials ? financials.normalized_other_revenue_details.select { |i| i.is_a?(Hash) && i["description"] == TicketSalesSync::PRODUCTS_LABEL }.sum { |i| (i["amount"].to_f * 100).round } : 0
    other = financials ? financials.normalized_other_revenue_details.select { |i| i.is_a?(Hash) && i["description"] != TicketSalesSync::PRODUCTS_LABEL }.sum { |i| (i["amount"].to_f * 100).round } : 0
    other += (financials.other_revenue.to_f * 100).round if financials && financials.normalized_other_revenue_details.empty?
    expenses = financials ? (financials.calculated_expenses * 100).round : 0
    fee = financials&.flat_fee? ? (financials.flat_fee.to_f * 100).round : 0
    # No revenue means none: whatever was typed before stays on the record
    # but counts for nothing while the show says so.
    if financials&.non_revenue_override?
      lines = []
      fee = 0
    end
    ShowPiece.new(show: show, financials: financials, listing: listing, ticket_lines: lines, outside_sources: outside,
                  products_cents: products, other_revenue_cents: other, expenses_cents: expenses, flat_fee_cents: fee,
                  pay_cell: Cell.new { pay_for(organization, show) })
  end

  # Who gets paid from a show, as it stands (Tim, 2026-11-04): a show on a
  # contract settles on the contract's payments for it; otherwise the
  # production's payout calculation pays the people cast, worked out from
  # the money once it's confirmed (a preview before that). A production
  # that doesn't pay its performers pays nobody.
  def self.pay_for(organization, show)
    production = show.production
    contract = show.space_rental&.contract || production.contract || show.contract_payments.first&.contract
    payments = contract ? contract_payments_for(show, contract).select(&:direction_outgoing?) : []
    blank = { rows: [], payments: [], hold_reason: nil, calc: :none, preview_cents: nil, preview_count: nil }
    if contract && (payments.any? || production.third_party? || contract.revenue_share?)
      return Pay.new(**blank, kind: :contract, show: show, show_payout: nil, scheme: nil, payments: payments)
    end
    return Pay.new(**blank, kind: :none, show: show, show_payout: nil, scheme: nil) unless production.pays_performers?
    # A show with no revenue pays nobody (Tim, 2026-11-04).
    return Pay.new(**blank, kind: :none, show: show, show_payout: nil, scheme: nil) if show.show_financials&.non_revenue_override?

    show_payout = show.show_payout
    show_payout = nil unless show_payout&.persisted?
    scheme = if production.asks_calculation_each_show?
      show_payout&.payout_scheme
    else
      show_payout&.payout_scheme || PayoutScheme.default_for_show(show)
    end
    hold = if scheme.nil?
      production.asks_calculation_each_show? ? "Choose this show's calculation first" : "Say how #{production.name} pays its performers first"
    end
    rules = (show_payout&.override_rules.presence || scheme&.rules || {}).deep_stringify_keys
    per_act = rules.dig("distribution", "method").to_s == "per_act"
    hold ||= "Enter how many acts each person did first" if per_act && !show.act_based? && show_payout&.act_counts.blank?
    return Pay.new(**blank, kind: :performers, show: show, show_payout: show_payout, scheme: scheme, hold_reason: hold) if hold

    # By show_id, not show:, so the dry-run payout never hangs off the show's
    # association as an unsaved record (the real one is created on Calculate).
    dry = show_payout || ShowPayout.new(show_id: show.id, payout_scheme: scheme)
    saved = show_payout&.calculated_at.present? && show_payout.line_items.any?
    preview = preview_rows(show, dry, rules)
    # The saved lines once worked out; before that, the people the numbers as they stand would pay.
    rows = if saved
      show_payout.line_items.includes(:payee, payout_contribution: :payout_batch).sort_by { |l| -l.amount.to_f }.map { |line| pay_row(line) }
    else
      preview
    end
    calc = if dry.act_payees.empty? then :no_cast
    elsif !per_act && !show.show_financials&.complete? then :needs_numbers
    elsif !saved then :uncalculated
    elsif numbers_changed_since?(show, show_payout.calculated_at)
      rows.any? { |r| r.stage.in?(%i[paid in_draft in_flight]) } ? :locked : :stale
    else :current
    end
    hold = { needs_numbers: "Enter the tickets or a flat fee first", uncalculated: "Calculate the payout first", stale: "The numbers changed; recalculate first" }[calc]
    Pay.new(kind: :performers, show: show, show_payout: show_payout, scheme: scheme, rows: rows, payments: [], hold_reason: hold, calc: calc,
            preview_cents: (calc.in?(%i[uncalculated stale]) ? preview.sum(&:cents) : nil), preview_count: (calc.in?(%i[uncalculated stale]) ? preview.size : nil))
  end

  # Whether the show's money or its cast moved after the payout was worked
  # out. Confirming a show restamps its calculation (the controller), so a
  # confirm alone never reads as a change.
  def self.numbers_changed_since?(show, calculated_at)
    [ show.show_financials&.updated_at, show.show_person_role_assignments.maximum(:updated_at), show.ticket_listing&.ticket_outside_sales&.maximum(:updated_at) ]
      .compact.any? { |t| t > calculated_at + 1.second }
  end

  def self.pay_row(line)
    batch = line.payout_contribution&.payout_batch
    stage, note = if line.paid?
      [ :paid, (line.manually_paid? ? "Paid another way#{line.payment_method_label ? " · #{line.payment_method_label}" : ''}" : "Paid, on a payout run") ]
    elsif batch&.open?
      [ :in_draft, "On the open payout run, a draft" ]
    elsif batch && PayoutBatchService::UNSETTLED_BATCH_STATUSES.include?(batch.status)
      [ :in_flight, "On its way" ]
    elsif line.held?
      [ :hold, "Held, not yet" ]
    else
      [ :run, "On the run when the day settles" ]
    end
    PayRow.new(line: line, payee: line.payee, name: line.payee_name, cents: (line.net_amount.to_d * 100).round, stage: stage, note: note)
  end

  # A dry run of the calculation, before the money is confirmed: the rows
  # it would make, keyed back to each payee. Empty when it can't run yet.
  def self.preview_rows(show, payout, rules)
    amounts = payout.preview_amounts(rules)
    return [] if amounts.empty?

    payout.act_payees.filter_map do |payee|
      cents = (amounts[ShowPayout.act_key(payee)].to_d * 100).round
      next if cents.zero? && !amounts.key?(ShowPayout.act_key(payee))

      PayRow.new(line: nil, payee: payee, name: (payee.respond_to?(:display_name) ? payee.display_name : payee.name), cents: cents, stage: :preview, note: nil)
    end
  end

  # The contract payments a show settles on (the same pick the show's payouts
  # page makes): the rows linked to it, its settlement however it's found,
  # and anything due that day.
  def self.contract_payments_for(show, contract)
    linked = show.contract_payments.includes(contract: :contractor).order(:due_date).to_a
    settlement = contract.find_payment_for_show(show)
    same_day = show.date_and_time ? contract.contract_payments.where(show_id: nil, due_date: show.date_and_time.to_date).to_a : []
    (linked + [ settlement ].compact + same_day).uniq(&:id).sort_by { |p| [ p.due_date || Date.new(1), p.id ] }
  end

  # A dot's name on the rail: the show's name, short.
  def self.short_name(show)
    # The name the show's card wears, so a dot and its card read the same.
    show.display_name.to_s.truncate(14, omission: "…")
  end

  # Whether a show is paid from its day's Settle up page: on or after the
  # organization's Settle up start date. Earlier shows keep their own pages.
  def self.in_settle_up?(organization, show)
    starts = organization.settle_up_starts_on
    return false unless starts && show.date_and_time

    SettlementDay.day_for(organization, show.date_and_time) >= starts
  end

  # Where a show's money is entered: its day on Settle up, the card open.
  # A show from before the start date has only its record, which says how
  # to bring it into Settle up (Tim, 2026-11-04: no going backwards).
  def self.money_entry_path(organization, show)
    routes = Rails.application.routes.url_helpers
    return routes.manage_money_show_financials_path(show) unless in_settle_up?(organization, show)

    routes.manage_money_settle_up_day_path(SettlementDay.day_for(organization, show.date_and_time).iso8601, open: show.id, anchor: "show-#{show.id}")
  end

  # The day a show settles on, and whether it has: [date, settled?].
  def self.day_state_for(organization, show)
    date = SettlementDay.day_for(organization, show.date_and_time)
    [ date, SettlementDay.where(organization: organization, date: date).settled.exists? ]
  end

  # Of these shows, the ones whose day is in Settle up and not settled yet:
  # their payouts ride the run when the day settles, so nothing else should
  # list them as money to pay by hand.
  def self.awaiting_settlement(organization, shows)
    starts = organization.settle_up_starts_on
    return [] unless starts

    candidates = shows.select { |s| s.date_and_time && SettlementDay.day_for(organization, s.date_and_time) >= starts }
    return [] if candidates.empty?

    settled = SettlementDay.where(organization: organization, date: candidates.map { |s| SettlementDay.day_for(organization, s.date_and_time) }.uniq).settled.pluck(:date).to_set
    candidates.reject { |s| settled.include?(SettlementDay.day_for(organization, s.date_and_time)) }
  end

  # Cash taken at the door for the day's shows (tickets and products paid
  # in cash), which should be in the box at close.
  def self.door_cash(organization, date, shows, record, cash: nil)
    listing_ids = shows.filter_map { |s| s.ticket_listing&.id }
    if cash
      rows = listing_ids.map { |id| cash.fetch(id, [ 0, 0, 0 ]) }
      return DoorCash.new(expected_cents: rows.sum { |taken, refunded, _| taken - refunded }, cash_orders_count: rows.sum(&:last), record: record)
    end

    orders = listing_ids.any? ? TicketOrder.where(ticket_listing_id: listing_ids, money_path: "cash", status: TicketOrder::WAS_PAID) : TicketOrder.none
    DoorCash.new(expected_cents: orders.sum(:total_cents) - orders.sum(:refunded_cents), cash_orders_count: orders.count, record: record)
  end
end

# frozen_string_literal: true

# The single source of truth for "what still needs doing about money?" —
# financials nobody has entered, payouts nobody has sent, money nobody has
# collected. Used by the Money hub and by the three pages it links to.
#
# It exists because the same questions were being asked in several places with
# slightly different SQL. "This show still needs financials" was written four
# times, with two different cutoffs and two different opinions about canceled
# shows, so the count on the Money page and the count on the Financials page
# could legitimately differ by a show. A hub that disagrees with the page it
# links to is worse than no hub, so the definitions live here now and every
# screen asks the same question.
#
#   MoneyTodoService.shows_awaiting_financials(productions)  # the predicate, anywhere
#   MoneyTodoService.new(user:, organization:, row_limit: 5) # the hub's three sections
#
# row_limit truncates each section's `items` and nothing else — `count` and
# `amount` always describe the whole set, so a hub showing five rows still says
# "23" and still totals all 23.
class MoneyTodoService
  include Rails.application.routes.url_helpers

  # How far ahead the hub looks for money owed to us. Overdue always counts,
  # whatever the horizon.
  INCOMING_HORIZON = 30.days

  # count/amount describe everything; items is what's rendered (possibly fewer).
  Section = Struct.new(:count, :amount, :amounts, :columns, :items,
                       :overdue_count, :overdue_amount, keyword_init: true) do
    def any? = count.to_i.positive?
    def truncated? = count.to_i > items.size
  end

  # --- The canonical predicates -------------------------------------------
  #
  # Class-level so a page can adopt one without paying to build the others.

  # Revenue shows that have already started but whose financials nobody has
  # confirmed. Canceled shows are excluded — there's nothing to enter — and the
  # cutoff is "has it happened yet", not "will it have happened by tomorrow".
  def self.shows_awaiting_financials(productions, as_of: Time.current)
    ids = production_ids_for(productions)
    return Show.none if ids.empty?

    Show.where(production_id: ids, event_type: EventTypes.revenue_event_types)
        .where(canceled: false)
        .where("date_and_time <= ?", as_of)
        .left_joins(:show_financials)
        .where("show_financials.id IS NULL OR show_financials.data_confirmed = FALSE OR show_financials.data_confirmed IS NULL")
  end

  def self.pending_financials_counts_by_production(productions, as_of: Time.current)
    shows_awaiting_financials(productions, as_of: as_of).group("shows.production_id").count
  end

  # The same question asked of a show that's already loaded — for filtering an
  # in-memory list without a second round trip.
  def self.awaiting_financials?(show, as_of: Time.current)
    return false unless EventTypes.revenue_event_types.include?(show.event_type)
    return false if show.canceled?
    return false if show.date_and_time > as_of

    !show.show_financials&.data_confirmed?
  end

  # Everything still owed to us, including charges that settle by deduction —
  # for totals, where the money is real even though nobody collects it.
  def self.all_incoming(organization)
    ContractPayment.direction_incoming.status_pending
                   .joins(:contract)
                   .where(contracts: { organization_id: organization.id })
  end

  # Money owed to us that somebody actually has to go and collect. Deduction-
  # settled charges net out of the counterparty's payout on their own, so
  # listing them as work inflates the pile with money nobody will ever invoice.
  def self.collectable_incoming(organization)
    all_incoming(organization).where.not(settlement_method: "payout_deduction")
  end

  def self.deduction_settled_incoming(organization)
    all_incoming(organization).where(settlement_method: "payout_deduction")
  end

  def self.production_ids_for(productions)
    case productions
    when ActiveRecord::Relation then productions.pluck(:id)
    else Array(productions).map { |p| p.is_a?(Integer) ? p : p.id }
    end
  end

  # --- The hub's sections --------------------------------------------------

  def initialize(user:, organization:, row_limit: nil)
    @user = user
    @organization = organization
    @row_limit = row_limit
  end

  attr_reader :user, :organization, :row_limit

  def financials
    @financials ||= begin
      base = self.class.shows_awaiting_financials(productions)
      items = base.includes(:production, :show_financials)
                  .order(date_and_time: :desc)
                  .limit(row_limit)
                  .to_a
      Section.new(count: base.count, items: items)
    end
  end

  # Productions, courses and contracts with money still to move, most
  # actionable first. Each row carries a per-status breakdown (to pay / in a
  # draft run / in flight / paid) so it answers "what have I done about this?"
  def payouts
    @payouts ||= begin
      items = production_payout_items + course_payout_items + contract_payout_items
      items.sort_by! { |i| [ -i[:amounts][:to_pay].to_f, -i[:amount].to_f ] }

      columns = [ :to_pay ]
      %i[in_draft in_flight paid].each do |col|
        columns << col if items.any? { |i| i[:amounts][col].to_f > 0.004 }
      end
      link_production_items!(items, columns)

      totals = Hash.new(0.0)
      items.each { |i| i[:amounts].each { |col, amount| totals[col] += amount.to_f } }

      Section.new(count: items.size,
                  amount: items.sum { |i| i[:amount].to_f },
                  amounts: totals,
                  columns: columns,
                  items: row_limit ? items.first(row_limit) : items)
    end
  end

  # Money owed to us that's late or lands inside the horizon. TBD amounts count
  # as rows but contribute nothing to the dollar totals — there's no figure yet.
  def incoming
    @incoming ||= begin
      horizon = Date.current + INCOMING_HORIZON
      base = self.class.collectable_incoming(organization).where(due_date: ..horizon)
      rows = base.by_due_date.includes(contract: [ :contractor, :production ]).to_a
      overdue = rows.select(&:overdue?)

      Section.new(count: rows.size,
                  amount: sum_amounts(rows),
                  overdue_count: overdue.size,
                  overdue_amount: sum_amounts(overdue),
                  items: row_limit ? rows.first(row_limit) : rows)
    end
  end

  def sections = [ financials, payouts, incoming ]

  def any? = sections.any?(&:any?)

  private

  def productions
    @productions ||= user.accessible_productions.to_a
  end

  def sum_amounts(payments)
    payments.reject(&:amount_tbd?).sum { |p| p.amount.to_f }
  end

  # --- Payouts, by source --------------------------------------------------

  # Every show with someone still unpaid, across every accessible production,
  # in three queries — not three per production. The old version priced every
  # production with a full FinancialSummaryService pass just to decide whether
  # it belonged in the list at all.
  def awaiting_shows_by_production
    @awaiting_shows_by_production ||= compute_awaiting_shows_by_production
  end

  def compute_awaiting_shows_by_production
    ids = productions.map(&:id)
    return {} if ids.empty?

    unpaid_payout_ids = ShowPayoutLineItem
      .joins(show_payout: :show)
      .where(shows: { production_id: ids })
      .where.not(show_payouts: { calculated_at: nil })
      .unpaid.distinct.pluck(:show_payout_id)
    return {} if unpaid_payout_ids.empty?

    Show.where(id: ShowPayout.where(id: unpaid_payout_ids).select(:show_id))
        .includes(show_payout: { line_items: { payout_contribution: :payout_batch } })
        .order(date_and_time: :desc)
        .group_by(&:production_id)
  end

  def production_payout_items
    by_production = awaiting_shows_by_production
    return [] if by_production.empty?

    productions.filter_map do |production|
      shows = by_production[production.id]
      next if shows.blank?

      breakdown = self.class.payout_breakdown(shows.flat_map { |s| s.show_payout.line_items })
      amounts = breakdown[:amounts]
      counts = breakdown[:counts]

      # Say what state the money is in, not just that it exists.
      parts = [ "#{shows.size} #{'show'.pluralize(shows.size)}" ]
      parts << "#{counts[:to_pay]} #{'person'.pluralize(counts[:to_pay])} to pay" if counts[:to_pay].positive?
      parts << "#{counts[:in_draft]} in a draft run" if counts[:in_draft].positive?
      parts << "#{counts[:in_flight]} in flight" if counts[:in_flight].positive?
      parts << "#{counts[:paid]} already paid" if counts[:paid].positive?

      { name: production.name, kind: :production,
        amount: amounts[:to_pay] + amounts[:in_draft] + amounts[:in_flight],
        amounts: amounts,
        subtitle: parts.join(" · "),
        production: production,
        awaiting_shows: shows }
    end
  end

  def course_payout_items
    items = []
    user.accessible_productions.courses
        .includes(course_offerings: { course_offering_payout: :line_items }).each do |course|
      # One course can hold many runs — surface each run's own payout. Course
      # instructor payouts are settled directly (never staged in a run).
      course.course_offerings.each do |offering|
        payout = offering.course_offering_payout
        next unless payout

        unpaid = payout.line_items.reject(&:paid?)
        paid = payout.line_items.select(&:paid?)
        amount = unpaid.sum(&:amount_cents) / 100.0
        next unless amount.positive?

        subtitle = +"#{unpaid.count} instructor #{'payout'.pluralize(unpaid.count)} to pay"
        subtitle << " · #{paid.count} already paid" if paid.any?

        items << { name: offering.title, kind: :course, amount: amount,
                   amounts: { to_pay: amount, paid: paid.sum(&:amount_cents) / 100.0 },
                   subtitle: subtitle,
                   href: manage_course_offering_payout_path(offering) }
      end
    end
    items
  end

  def contract_payout_items
    items = []
    organization.contracts
                .includes({ contract_payments: { payout_contribution: :payout_batch } }, :contractor).each do |contract|
      outgoing = contract.contract_payments.select(&:direction_outgoing?)
      pending = outgoing.select(&:status_pending?)
      amount = pending.sum { |p| p.amount.to_f }
      next unless amount.positive?

      # Contract payments can be staged in payout runs too — split them the
      # same way as show payouts.
      by_col = pending.group_by { |p| self.class.payout_bucket(p.payout_contribution&.payout_batch, paid: false) }
      paid_payments = outgoing.select(&:status_paid?)
      amounts = by_col.transform_values { |ps| ps.sum { |p| p.amount.to_f } }
      amounts[:paid] = paid_payments.sum { |p| p.amount.to_f }

      parts = [ "#{pending.count} contract #{'payment'.pluralize(pending.count)} due" ]
      due = pending.filter_map(&:due_date).min
      if due
        due_label = pending.size == 1 ? "due" : "next due"
        parts << (due < Date.current ? "overdue since #{due.strftime('%b %-d')}" : "#{due_label} #{due.strftime('%b %-d')}")
      end
      parts << "#{by_col[:in_draft].size} in a draft run" if by_col[:in_draft].present?
      parts << "#{by_col[:in_flight].size} in flight" if by_col[:in_flight].present?
      parts << "#{paid_payments.count} already paid" if paid_payments.any?

      items << { name: contract.contractor_name, kind: :contract, amount: amount,
                 amounts: amounts,
                 subtitle: parts.join(" · "),
                 href: manage_contract_path(contract) }
    end
    items
  end

  # Production rows link once the column set is known — the accordion carries it
  # in the URL so its inline show rows line up with the grid. Go straight to the
  # payout needing attention: one awaiting show links to it, several open an
  # accordion.
  def link_production_items!(items, columns)
    cols_param = columns.join(",")
    items.each do |item|
      shows = item.delete(:awaiting_shows) || next
      production = item.delete(:production)
      if shows.size == 1
        item[:href] = manage_money_show_payout_path(shows.first)
      else
        item[:expand_src] = manage_money_production_payout_events_path(production, awaiting: 1, cols: cols_param)
        item[:expand_id] = "awaiting-events-#{production.id}"
      end
    end
  end

  # --- Bucketing (one implementation, used by the grid helper too) ----------

  # Which column a piece of money belongs in: nobody's touched it, it's staged
  # in an unsubmitted run, it's in a submitted one, or it's out the door.
  def self.payout_bucket(batch, paid:)
    return :paid if paid
    return :to_pay if batch.nil?

    if batch.status == "draft"
      :in_draft
    elsif PayoutBatchService::UNSETTLED_BATCH_STATUSES.include?(batch.status)
      :in_flight
    else
      :to_pay
    end
  end

  # Splits show-payout line items into the four buckets.
  # { amounts: {col => Float}, counts: {col => Integer} } — amounts are the
  # payees' nets, counts are people.
  def self.payout_breakdown(line_items)
    amounts = Hash.new(0.0)
    counts = Hash.new(0)
    line_items.each do |item|
      col = payout_bucket(item.payout_contribution&.payout_batch, paid: item.paid?)
      amounts[col] += item.net_amount.to_f
      counts[col] += 1
    end
    { amounts: amounts, counts: counts }
  end
end

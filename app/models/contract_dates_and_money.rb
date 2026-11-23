# frozen_string_literal: true

# A contract's dates and its money as one list (Tim, 2026-11-22, the contract
# page's "Dates and money", design B on
# https://claude.ai/artifact/62bco7jZ8dU8ZQU5C7XhvU): one row per booked date
# carrying what that date brought in or cost, in date order.
#
# - A payment that belongs to one date (a rehearsal's charge, a night's share)
#   is a line in that date's row.
# - A payment due on a day with nothing booked (a deposit, one added by hand),
#   and a settlement that covers several nights (a week, a month), is a row of
#   its own at its date: money only. Each night it covers says so.
# - What's left owed when no share is left to take it out of (a charge's
#   carried balance) is not tied to a date at all: it's `owed`, the box under
#   the list. One set to $0 stays there, settled.
#
# Rows carry the payments to draw when a row is opened (the page's own
# payment rows, with every action they have), and open themselves when one of
# them needs doing today.
class ContractDatesAndMoney
  Line = Data.define(:text, :amount, :note, :tone) do
    def owed? = tone == :owed
  end

  # kind: :night (a booked date) or :payment (money only, no booking).
  Row = Data.define(:kind, :date, :rental, :show, :payment, :title, :subtitle, :lines,
                    :expanded, :charges, :open) do
    def night? = kind == :night
    def owed? = lines.any?(&:owed?)
    def key = night? ? "night-#{rental&.id || "show-#{show&.id}"}" : "payment-#{payment.id}"
  end

  # One charge on a date, however many rows it became: a rehearsal a share
  # only partly covered is the covered part plus a carried "Rehearsal balance"
  # row, each settled its own way.
  Charge = Data.define(:name, :pieces) do
    def total = pieces.sum { |p| ContractDatesAndMoney.piece_amount(p) }
  end

  attr_reader :contract

  def initialize(contract, payments: nil, rentals: nil)
    @contract = contract
    @payments = (payments || contract.contract_payments.by_due_date).to_a
    @rentals = (rentals || contract.space_rentals.includes(:location, :location_space).order(:starts_at)).to_a
  end

  def self.piece_amount(payment)
    payment.set_to_zero? ? payment.amount_before_change.to_f : payment.amount.to_f
  end

  # The page's payment groups (Contract#payment_schedule_groups), by payment:
  # a settlement with the charges netted out of it, and any shares settled
  # with it by one offset.
  def groups
    @groups ||= contract.payment_schedule_groups(@payments).index_by { |g| g[:payment].id }
  end

  # The settlement a charge was (or will be) netted out of, for a charge's
  # working: "Oct 25 — from the Oct 22 share".
  def host_for(charge_piece)
    @hosts ||= groups.values.each_with_object({}) do |g, h|
      g[:deductions].each { |d| h[d.id] = g[:payment] }
    end
    @hosts[charge_piece.id]
  end

  def rows
    @rows ||= (night_rows + payment_rows).sort_by { |r| [ r.date, r.night? ? 0 : 1, r.rental&.starts_at || r.date ] }
  end

  # --- What's still owed, under the list ---------------------------------------

  # A charge's carried balance with no share left to take it out of: owed
  # straight to the organization now, and not tied to any one date. One a
  # manager set to $0 stays here, settled.
  def owed
    @owed ||= live.select { |p| owed_box?(p) }.sort_by(&:due_date)
  end

  def owed_pending
    owed.select(&:status_pending?)
  end

  def owed_total
    owed_pending.sum { |p| p.amount.to_f }.round(2)
  end

  # "the rest of the rehearsal on Sep 13"
  def self.owed_label(payment)
    name, date = payment.billed_description.split(ContractPayment::BALANCE_SEPARATOR, 2)
    day = (Date.parse(date) rescue nil) if date
    day ||= payment.show&.date_and_time&.to_date || payment.due_date
    "the rest of the #{name.to_s.strip.downcase.presence || 'charge'} on #{day.strftime('%b %-d')}"
  end

  private

  def live
    @live ||= @payments.reject(&:status_cancelled?)
  end

  def owed_box?(payment)
    payment.direction_incoming? && payment.carried_balance? &&
      (payment.set_to_zero? || (payment.status_pending? && !payment.deduct_from_payout?))
  end

  def share_word
    @share_word ||= contract.revenue_share? || contract.ticket_revenue_minus_fee? ? "share" : "payment"
  end

  def ticket_deal?
    contract.revenue_share? || contract.ticket_revenue_minus_fee?
  end

  # --- Nights ---------------------------------------------------------------

  def shows
    @shows ||= contract.contract_shows.where(canceled: false).includes(:show_financials).to_a
  end

  def nights
    @nights ||= begin
      by_rental = shows.select(&:space_rental_id).index_by(&:space_rental_id)
      list = @rentals.map { |r| { date: r.starts_at.to_date, rental: r, show: by_rental[r.id] } }
      rental_ids = @rentals.map(&:id)
      # A show the contract's production holds without a booking still has a
      # date and money.
      shows.reject { |s| s.space_rental_id.in?(rental_ids) || s.date_and_time.nil? }.each do |s|
        list << { date: s.date_and_time.to_date, rental: nil, show: s }
      end
      list.sort_by { |n| n[:rental]&.starts_at || n[:show].date_and_time }
    end
  end

  # Which night a payment is a line of, or nil when it has none.
  def night_for(payment)
    return nil if contract.period_settlement?(payment)

    if payment.show_id
      nights.find { |n| n[:show]&.id == payment.show_id }
    else
      same_day = nights.select { |n| n[:date] == payment.due_date }
      same_day.first if same_day.one?
    end
  end

  def payments_by_night
    @payments_by_night ||= @payments.group_by { |p| night_for(p) }
  end

  def period_settlements
    @period_settlements ||= live.select { |p| contract.period_settlement?(p) }
  end

  # The settlement that covers a night, when the deal settles by the week or
  # the month (or the whole run).
  def covering_settlement(night)
    return nil unless night[:show]

    period_settlements.find { |p| contract.settlement_shows_for(p).any? { |s| s.id == night[:show].id } }
  end

  def night_rows
    nights.map do |night|
      own = payments_by_night.fetch(night, [])
      live_own = own.reject(&:status_cancelled?)
      lines = []
      label = night[:show]&.event_type && EventTypes.labels[night[:show].event_type.to_s]

      live_own.select(&:direction_outgoing?).each { |p| lines << outgoing_line(p, night) }
      charges = charges_for(live_own.select(&:direction_incoming?))
      charges.each { |c| lines << charge_line(c, prefix: c.name.casecmp?(label.to_s) ? nil : c.name) }

      if (settlement = covering_settlement(night))
        what = ticket_deal? ? "Ticket sales settle" : "Settles"
        lines << Line.new(text: "#{what} with #{settlement.display_name}, #{day(settlement.due_date)}.", amount: nil, note: nil, tone: :neutral)
      end
      lines << Line.new(text: "Nothing is due on this date.", amount: nil, note: nil, tone: :neutral) if lines.empty?

      expanded = own.select { |p| groups.key?(p.id) && !owed_box?(p) }
      working = charges.select { |c| c.pieces.any? { |p| deducted_or_deducting?(p) } }
      Row.new(kind: :night, date: night[:date], rental: night[:rental], show: night[:show], payment: nil,
              title: nil, subtitle: nil, lines: lines, expanded: expanded, charges: working,
              open: expanded.any? { |p| needs_doing?(p) })
    end
  end

  # --- Money on days with nothing booked ---------------------------------------

  def payment_rows
    night_ids = payments_by_night.reject { |night, _| night.nil? }.values.flatten.map(&:id)
    @payments.select { |p| groups.key?(p.id) && !night_ids.include?(p.id) && !owed_box?(p) }.map do |p|
      covered = contract.period_settlement?(p) ? contract.settlement_shows_for(p).filter_map(&:date_and_time).sort : []
      subtitle =
        if covered.any?
          "Covers #{covered.map { |t| day(t.to_date) }.to_sentence}"
        else
          "Nothing is booked this day"
        end
      line = p.direction_outgoing? ? outgoing_line(p, nil) : charge_line(Charge.new(name: p.display_name, pieces: [ p ]), prefix: nil)
      Row.new(kind: :payment, date: p.due_date, rental: nil, show: nil, payment: p,
              title: p.description.presence || "Payment", subtitle: subtitle, lines: p.status_cancelled? ? [] : [ line ],
              expanded: [ p ], charges: [], open: needs_doing?(p))
    end
  end

  # --- Lines ------------------------------------------------------------------

  def outgoing_line(payment, night)
    sold = sold_text(night)
    status =
      if payment.status_paid?
        if payment.payment_method == "offset"
          "The #{money(payment.amount)} #{share_word} went toward what #{contract.contractor_name} owed. Settled #{day(payment.paid_date)}."
        else
          via = payment.offline_payment_method_label
          "Paid #{day(payment.paid_date)}#{" (#{via.downcase})" if via}."
        end
      elsif payment.in_payout_run?
        payment.payout_stage == :in_flight ? "Paid, and on its way to #{contract.contractor_name}'s bank." : "In the payout run."
      elsif payment.nothing_to_hand_back?
        "Ticket sales covered our fee exactly, so nothing is paid."
      elsif payment.awaiting_amount? || payment.amount_tbd?
        night && night[:date] > Date.current ? "Settles after the show." : "Waiting on ticket sales."
      elsif payment.settles_after_show?
        "Settles after the show."
      elsif payment.late?
        "Due #{day(payment.due_date)}, and overdue."
      else
        "Due #{day(payment.due_date)}."
      end
    amount = payment.amount_tbd? && payment.amount.to_f.zero? ? nil : money(payment.amount)
    tone = payment.payment_method == "offset" ? :offset : (payment.late? && !payment.in_payout_run? ? :owed : :neutral)
    Line.new(text: [ sold, status ].compact.join(" "), amount: amount, note: share_word == "share" ? "Share" : "We pay", tone: tone)
  end

  def sold_text(night)
    return nil unless ticket_deal? && night && night[:show]

    financials = night[:show].show_financials
    return nil unless financials&.has_data?

    so_far = night[:date] > Date.current ? " so far" : ""
    "Sold #{money(contract.settled_revenue(financials))}#{so_far}."
  end

  # Incoming payments on a date, one charge per thing billed: the original
  # row and the carried balances it became.
  def charges_for(incoming)
    incoming.group_by(&:billed_description).map do |description, pieces|
      Charge.new(name: description.to_s.split(ContractPayment::BALANCE_SEPARATOR, 2).first.to_s.strip.presence || "Payment",
                 pieces: pieces.sort_by(&:id))
    end
  end

  def charge_line(charge, prefix:)
    deducted = charge.pieces.select { |p| p.status_paid? && p.payment_method == "payout_deduction" }
    zeroed = charge.pieces.select(&:set_to_zero?)
    paid = charge.pieces.select(&:status_paid?) - deducted - zeroed
    pending = charge.pieces.select(&:status_pending?)
    mixed = [ deducted, paid, zeroed, pending ].count(&:any?) > 1
    sum = ->(list) { money(list.sum { |p| self.class.piece_amount(p) }) }
    dates = ->(list) { list.filter_map(&:paid_date).uniq.sort.map { |d| day(d) }.to_sentence }

    parts = []
    parts << "#{mixed ? "#{sum.(deducted)} paid" : 'Paid'} from the #{share_word}s on #{dates.(deducted)}." if deducted.any?
    if paid.any?
      via = paid.filter_map(&:received_via_label).first
      lead = mixed ? "#{sum.(paid)} paid" : "Paid"
      parts << "#{lead}#{via == 'Paid online' ? ' online' : ''} on #{dates.(paid)}."
    end
    parts << "#{mixed ? "#{sum.(zeroed)} set" : 'Set'} to $0 on #{dates.(zeroed)}." if zeroed.any?
    if pending.any?
      if pending.all?(&:deduct_from_payout?)
        parts << "#{mixed ? "#{sum.(pending)} comes" : 'Comes'} out of the next #{share_word}."
      elsif mixed
        parts << "#{sum.(pending)} is still owed."
      else
        first = pending.min_by(&:due_date)
        parts << (pending.any?(&:late?) ? "Due #{day(first.due_date)}, and overdue." : "Due #{day(first.due_date)}.")
      end
    end

    owing = pending.reject(&:deduct_from_payout?)
    note =
      if owing.any? then "#{sum.(owing)} owed"
      elsif pending.any? then "Due"
      elsif zeroed.any? && deducted.empty? && paid.empty? then "Set to $0"
      else "Paid"
      end
    text = parts.join(" ")
    text = "#{prefix}: #{text[0].downcase}#{text[1..]}" if prefix && text.present?
    Line.new(text: text, amount: money(charge.total), note: note, tone: owing.any? ? :owed : :neutral)
  end

  def deducted_or_deducting?(payment)
    (payment.status_paid? && payment.payment_method == "payout_deduction") ||
      (payment.status_pending? && payment.deduct_from_payout?)
  end

  # Something to do about it today: due or overdue, not already on its way,
  # and not waiting on a show still to come.
  def needs_doing?(payment)
    payment.status_pending? && !payment.in_payout_run? && !payment.settles_after_show? &&
      !payment.deduct_from_payout? && payment.due_date.present? && payment.due_date <= Date.current
  end

  def money(value)
    ActiveSupport::NumberHelper.number_to_currency(value.to_f)
  end

  def day(date)
    date.strftime("%b %-d")
  end
end

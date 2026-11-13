# frozen_string_literal: true

# How a contract's settlement gets to its number, line by line (Tim,
# 2026-11-13: "show the whole breakdown, the entire breakdown of how it got to
# that number"): each night's ticket sales, our fee or their share, what they
# owe that comes out of it, and what's left, whichever way it faces. One
# working for the contract page's row, Settle up's "Who gets paid" and the
# View calculation window, so the three can't say different numbers.
#
# A settlement for a stretch of shows that isn't finished (a week with a
# night still to come, or a day not settled yet) is "so far": the same lines
# from sales as they stand, with nothing to pay or collect until it's over.
class ContractSettlementWorking
  Line = Data.define(:label, :cents, :kind) do
    # :sales and :fee and :share add up to the settlement; :charge comes out
    # of it; :note is a line of words with a number that isn't added in.
    def counted? = kind != :note
  end

  attr_reader :payment, :contract, :charges

  def self.for(payment, charges: nil)
    new(payment, charges: charges)
  end

  # charges: what they owe that rides this settlement, when the caller has
  # the contract's groups already; worked out here otherwise.
  def initialize(payment, charges: nil)
    @payment = payment
    @contract = payment.contract
    @charges = charges || find_charges
  end

  def shows
    @shows ||= contract.settlement_shows_for(payment).select(&:date_and_time).sort_by(&:date_and_time)
  end

  def in_progress? = contract.settlement_in_progress?(payment)
  def period? = contract.period_settlement?(payment) && shows.many?
  def last_show = shows.last

  # Their side of the settlement before charges, in cents: positive is money
  # to them, negative is a shortfall they owe.
  #
  # A minus-fee stretch still in progress is worked out here, from every
  # night's sales as they stand less the fee for every night it covers: the
  # payment's own amount only counts the nights whose numbers are in, so a
  # week one night in read as that night's alone.
  def settlement_cents
    return sales_cents - fee_cents if contract.ticket_revenue_minus_fee? && (in_progress? || payment.awaiting_amount?)

    cents = (payment.amount.to_d * 100).round
    payment.direction_incoming? ? -cents : cents
  end

  def charges_cents = charges.sum { |c| (c.amount.to_d * 100).round }

  # What moves once it's settled: positive, we pay them; negative, they pay us.
  def net_cents = settlement_cents - charges_cents

  def sales_cents
    shows.sum { |show| sales_for(show) }
  end

  # Our fee across the shows (a minus-fee deal): what's kept out of sales.
  def fee_cents
    return 0 unless contract.ticket_revenue_minus_fee?

    (contract.flat_fee_for_shows(shows).to_d * 100).round
  end

  def lines
    @lines ||= sales_lines + settlement_lines + charge_lines
  end

  # Days of this stretch an organization that settles up hasn't settled.
  def unsettled_days
    @unsettled_days ||= SettleUp.awaiting_settlement(contract.organization, shows)
                               .map { |show| SettlementDay.day_for(contract.organization, show.date_and_time) }.uniq.sort
  end

  def nights_to_come = shows.select { |show| show.date_and_time > Time.current }

  # When it's paid, in words: "after Sat, Nov 14's show, with the week's
  # other shows", then "once Nov 12 and Nov 13 are settled".
  def when_words
    return nil unless in_progress?

    if nights_to_come.any?
      night = last_show.date_and_time.strftime("%a, %b %-d")
      together = period? ? ", together with #{stretch_words}" : ""
      "after #{night}'s show#{together}"
    else
      days = unsettled_days.map { |d| d.strftime("%b %-d") }
      "once #{days.to_sentence} #{days.one? ? 'is' : 'are'} settled"
    end
  end

  # What to call it: a stretch in progress by what it is ("The week so
  # far"), since its payment's own name changes with the way it faces.
  def title
    return payment.display_name unless in_progress? && period?

    case contract.settlement_cadence
    when "weekly" then "The week so far"
    when "monthly" then "The month so far"
    else "The run so far"
    end
  end

  def stretch_words
    case contract.settlement_cadence
    when "weekly" then "the week's other shows"
    when "monthly" then "the month's other shows"
    else "the run's other shows"
    end
  end

  # "We pay them" / "They pay us" / "Nothing moves", as it stands.
  def direction_words
    return "Nothing moves" if net_cents.zero?
    # Their share didn't cover what they owe: the rest comes out of their
    # next share, it isn't a bill.
    return "They still owe" if net_cents.negative? && payment.direction_outgoing? && !in_progress?

    net_cents.positive? ? "We pay them" : "They pay us"
  end

  private

  def sales_for(show)
    (contract.settled_revenue(show.show_financials).to_d * 100).round
  end

  def day(show) = show.date_and_time.strftime("%b %-d")

  def sales_lines
    kind = contract.ticket_revenue_minus_fee? ? :sales : :note
    return [ Line.new(label: "Ticket sales", cents: sales_cents, kind: kind) ] if shows.size > Contract::FEE_LINES_LIMIT || shows.empty?

    shows.map do |show|
      to_come = show.date_and_time > Time.current
      label = shows.one? ? "Ticket sales" : "Ticket sales — #{day(show)}"
      Line.new(label: to_come ? "#{label} (so far)" : label, cents: sales_for(show), kind: kind)
    end
  end

  # A minus-fee deal: our fee comes out of sales, night by night when the
  # nights' fees add up to it. Anything else (a split): their share as the
  # payment holds it.
  def settlement_lines
    if contract.ticket_revenue_minus_fee?
      kept = sales_cents - settlement_cents
      return [] if kept.zero?

      nightly = contract.fee_by_night(shows, total: kept / 100.0)
      return nightly.map { |show, fee| Line.new(label: (nightly.many? ? "Our fee — #{day(show)}" : "Our fee"), cents: -(fee.to_d * 100).round, kind: :fee) } if nightly

      [ Line.new(label: "Our fee", cents: -kept, kind: :fee) ]
    else
      percent = contract.respond_to?(:contractor_share_percentage) ? contract.contractor_share_percentage : nil
      label = percent ? "Their #{percent.to_f.round(2).to_s.sub(/\.0\z/, '')}% share" : "Their share"
      [ Line.new(label: label, cents: settlement_cents, kind: :share) ]
    end
  end

  def charge_lines
    charges.sort_by { |c| [ c.due_date || Date.new(1), c.id ] }
           .map { |c| Line.new(label: c.description.presence || c.display_name, cents: -(c.amount.to_d * 100).round, kind: :charge) }
  end

  def find_charges
    group = contract.payment_schedule_groups.detect { |g| g[:payment].id == payment.id }
    Array(group && group[:deductions])
  end
end

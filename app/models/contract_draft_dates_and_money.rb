# frozen_string_literal: true

# The dates and money a contract out for signature was sent with (Tim,
# 2026-11-23: "I have no way to see what dates we've submitted for this show
# while we're waiting for them to review it"). Until it's signed a contract's
# bookings and payments live only in its draft (Contract#draft_bookings,
# #billed_draft_payments); signing turns them into space rentals and payment
# rows, which ContractDatesAndMoney draws. This draws the draft the same way:
# one row per date with what's due on it, and money due on a day with nothing
# booked (a weekly settlement, a deposit) as a row of its own.
class ContractDraftDatesAndMoney
  Line = Data.define(:text, :amount, :note)
  Row = Data.define(:kind, :date, :starts_at, :ends_at, :event_type, :place, :show_time, :title, :subtitle, :lines) do
    def night? = kind == :night
  end

  attr_reader :contract

  def initialize(contract)
    @contract = contract
  end

  def rows
    @rows ||= (night_rows + payment_rows).sort_by { |r| [ r.date, r.night? ? 0 : 1, r.starts_at || r.date.beginning_of_day ] }
  end

  def date_count = bookings.size
  def payment_count = payments.size

  private

  def bookings
    @bookings ||= contract.draft_bookings.filter_map do |booking|
      starts = parse_time(booking["starts_at"])
      next unless starts

      ends = parse_time(booking["ends_at"]) || (booking["duration"].present? ? starts + booking["duration"].to_f.hours : nil)
      { booking: booking, starts_at: starts, ends_at: ends, date: starts.to_date }
    end.sort_by { |b| b[:starts_at] }
  end

  def payments
    @payments ||= (contract.billed_draft_payments.select { |p| p.is_a?(Hash) } + contract.draft_event_rate_charges).map do |p|
      p.merge("_date" => (Date.parse(p["due_date"].to_s) rescue nil))
    end
  end

  # A payment due on a day with exactly one booking is a line of that date,
  # unless it settles a week, a month, or the run: that's a row of its own,
  # as on the signed contract (ContractDatesAndMoney#night_for).
  def night_for(payment)
    return nil unless payment["_date"]
    return nil if !payment["event_rate"] && period_settlement?(payment)

    same_day = bookings.select { |b| b[:date] == payment["_date"] }
    same_day.first if same_day.one?
  end

  def period_settlement?(payment)
    contract.period_settlement?(
      ContractPayment.new(description: payment["description"].to_s, direction: payment["direction"].presence || "outgoing",
                          amount_tbd: ActiveModel::Type::Boolean.new.cast(payment["amount_tbd"]) || false)
    )
  end

  def payments_by_night
    @payments_by_night ||= payments.group_by { |p| night_for(p) }
  end

  def night_rows
    bookings.map do |b|
      lines = payments_by_night.fetch(b, []).map { |p| line_for(p) }
      lines << Line.new(text: "Nothing is due on this date.", amount: nil, note: nil) if lines.empty?
      Row.new(kind: :night, date: b[:date], starts_at: b[:starts_at], ends_at: b[:ends_at],
              event_type: b[:booking]["event_type"].presence || contract.default_event_type,
              place: place(b[:booking]), show_time: contract.booking_show_time_words(b[:booking]),
              title: nil, subtitle: nil, lines: lines)
    end
  end

  def payment_rows
    payments.select { |p| p["_date"] && night_for(p).nil? }.map do |p|
      Row.new(kind: :payment, date: p["_date"], starts_at: nil, ends_at: nil, event_type: nil, place: nil, show_time: nil,
              title: p["description"].presence || "Payment", subtitle: p["notes"].presence || "Nothing is booked this day",
              lines: [ line_for(p, with_note: false) ])
    end
  end

  def line_for(payment, with_note: true)
    incoming = payment["direction"] == "incoming"
    tbd = ActiveModel::Type::Boolean.new.cast(payment["amount_tbd"])
    due =
      if payment["settlement"] == "payout_deduction"
        "Comes out of the next payment to #{contract.contractor_name}."
      elsif payment["_date"]
        "Due #{payment['_date'].strftime('%b %-d')}."
      else
        "No due date yet."
      end
    # A rehearsal's charge is a line of its own date, so the date is already there.
    label = payment["event_rate"] ? payment["description"].to_s.split(" — ").first : payment["description"].presence
    text = with_note && label ? "#{label}: #{due[0].downcase}#{due[1..]}" : due
    text = "#{text} Worked out from ticket sales after the shows." if tbd && !incoming && contract.guarantee_amount_label(payment).nil?
    amount = tbd ? contract.guarantee_amount_label(payment) : ActiveSupport::NumberHelper.number_to_currency(payment["amount"].to_f)
    Line.new(text: text, amount: amount, note: incoming ? "They pay us" : "We pay")
  end

  def place(booking)
    location = locations[booking["location_id"].to_i]
    return nil unless location

    space_id = (booking["location_space_id"].presence || booking["space_id"].presence)&.to_i
    space = space_id && location.location_spaces.find { |s| s.id == space_id }
    [ space&.name || "Entire venue", location.name ].join(" at ")
  end

  def locations
    @locations ||= contract.organization.locations.includes(:location_spaces)
                           .where(id: contract.draft_bookings.filter_map { |b| b["location_id"].presence&.to_i }.uniq)
                           .index_by(&:id)
  end

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end

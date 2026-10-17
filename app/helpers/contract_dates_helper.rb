# frozen_string_literal: true

# Rows for a contract's dates (Review the dates, 2026-10-16): each booking with
# its kind, place and length, the terms the deal gives it (or its own), what it
# costs, and what Edit can change.
module ContractDatesHelper
  DateRow = Struct.new(:starts_at, :at, :event_type, :kind, :hours, :place, :field, :usual, :terms,
                       :line, :sub, :changed, :cost, :fixed_amount, :settled, keyword_init: true)

  # settled: start times (Time or epoch) of dates already settled, which keep
  # their terms: no Edit, no tick (an amendment's list).
  def contract_date_rows(contract, bookings, locations_map:, spaces_map:, settled: [])
    settled = Array(settled).map(&:to_i).to_set
    bookings.filter_map do |booking|
      at = (Time.zone.parse(booking["starts_at"].to_s) rescue nil)
      next unless at

      type = booking["event_type"].presence || "show"
      hours = booking_hours(booking, at)
      space = spaces_map[booking["space_id"].to_i] if booking["space_id"].present?
      location = locations_map[booking["location_id"].to_i]
      terms = contract.date_terms_for_booking(booking["starts_at"])
      line, sub, changed = contract.date_terms_words(type, terms)
      locked = settled.include?(at.to_i)
      field = (contract.date_term_field(type) unless locked)
      fixed = fixed_amount_for(contract, type, terms, hours)

      DateRow.new(starts_at: booking["starts_at"].to_s, at: at, event_type: type,
                  kind: EventTypes.labels[type] || type.titleize, hours: hours,
                  place: (space&.name || location&.name), field: field, usual: contract.usual_date_term(type),
                  terms: terms, line: line, sub: sub, changed: changed,
                  cost: cost_words(contract, type, terms, fixed), fixed_amount: fixed, settled: locked)
    end
  end

  # The event page's Contract box: the services this date gets from its
  # contract, each with what it costs here: [{ name:, hours:, amount: }].
  def contract_services_for_show(contract, show)
    key = show.space_rental&.starts_at&.to_i
    return [] unless contract && key

    contract.draft_services.filter_map do |line|
      next unless line["per_event"]

      event = Array(line["events"]).find { |e| ContractServicesChange.time_key(e["starts_at"]) == key }
      next unless event

      hourly = line["unit"] == "hourly"
      price = (event["unit_price"] || line["unit_price"]).to_f
      { name: line["name"], hours: (event["hours"].to_f if hourly), amount: (price * (hourly ? event["hours"].to_f : 1)).round(2) }
    end
  end

  # This date's payments on its contract (not cancelled): the ones tied to
  # the show, or due that day with no show of their own.
  def contract_payments_for_show(contract, show)
    return [] unless contract

    payments = contract.contract_payments.where.not(status: "cancelled")
    tied = payments.where(show_id: show.id).order(:due_date, :id).to_a
    tied.presence || payments.where(show_id: nil, due_date: show.date_and_time.to_date).order(:id).to_a
  end

  # One picture of a contract's deal for one date, for the show page's
  # Contract box (Tim, 2026-10-17: a producer should read it and know what
  # they get, that the amount waits on ticket sales, and that the services
  # come out of it): the date's terms, the payment to them (payout), each
  # service with how it's settled (:deducted from their share, :direct they
  # pay us, :paid), the other money they owe, and the services' total that
  # comes out of their share.
  def contract_date_picture(contract, show)
    services = contract_services_for_show(contract, show)
    payments = contract_payments_for_show(contract, show)
    payout = payments.find(&:direction_outgoing?)
    incoming = payments.select(&:direction_incoming?)
    rows = services.map do |service|
      charge = incoming.find do |payment|
        payment.description.to_s.start_with?("#{service[:name]} —") || payment.service_components.any? { |c| c["name"] == service[:name] }
      end
      how =
        if charge.nil? then nil
        elsif charge.settlement_method == "payout_deduction" then :deducted
        elsif charge.status_paid? then :paid
        else :direct
        end
      service.merge(charge: charge, how: how)
    end
    charged = rows.filter_map { |row| row[:charge] }.uniq
    terms = show.contract_terms.presence || {}
    {
      terms: contract.date_terms_words(show.event_type, terms),
      note: terms["note"].presence,
      payout: payout,
      services: rows,
      other_incoming: incoming - charged,
      deducted_total: rows.select { |row| row[:how] == :deducted }.sum { |row| row[:amount].to_f }.round(2)
    }
  end

  # "3 hrs" / "90 min".
  def date_length_words(hours)
    return nil unless hours&.positive?

    hours < 1 ? "#{(hours * 60).round} min" : "#{hours % 1 == 0 ? hours.to_i : hours.round(1)} #{'hr'.pluralize(hours)}"
  end

  # "8 dates booked" sub-line: "Oct 20 to Nov 6, 2026 · 5 shows, 3 rehearsals".
  def contract_dates_summary(rows)
    return nil if rows.empty?

    first, last = rows.map(&:at).minmax
    range = first.to_date == last.to_date ? first.strftime("%b %-d, %Y") : "#{first.strftime('%b %-d')} to #{last.strftime('%b %-d, %Y')}"
    kinds = rows.group_by(&:kind).map { |kind, rs| pluralize(rs.size, kind.downcase) }
    "#{range} · #{kinds.join(', ')}"
  end

  # What Edit asks for on this kind of date: { label:, unit: "$" | "%", help: }.
  def date_term_field_copy(contract, event_type)
    usual = contract.usual_date_term(event_type).to_f
    money = number_to_currency(usual, precision: usual % 1 == 0 ? 0 : 2)
    kind = (EventTypes.labels[event_type] || event_type.to_s.titleize)
    if (rate = contract.event_rate_for_type(event_type))
      per = rate["unit"] == "hourly" ? " an hour" : " per #{kind.downcase}"
      { label: "#{kind} rate for this date", unit: "$", help: "Usually #{money}#{per}. $0 means no charge." }
    elsif contract.per_event_deal?
      { label: "This date's fee", unit: "$", help: "Usually #{money} per event. $0 means no charge." }
    elsif contract.date_term_field(event_type) == :share
      pct = usual % 1 == 0 ? usual.to_i : usual
      { label: "Our share for this show", unit: "%", help: "Usually #{pct}%. 0% means they keep this show's ticket sales." }
    else
      { label: "Our fee for this show", unit: "$", help: "Usually #{money}. $0 means they get all of it." }
    end
  end

  private

  def booking_hours(booking, at)
    if booking["ends_at"].present?
      ends = (Time.zone.parse(booking["ends_at"].to_s) rescue nil)
      return ((ends - at) / 3600.0).round(2) if ends
    end
    booking["duration"].to_f.positive? ? booking["duration"].to_f : nil
  end

  # Dollars this date costs on its own (a rehearsal's rate, a per-event fee),
  # nil when it rides on ticket sales or a whole-contract fee.
  def fixed_amount_for(contract, type, terms, hours)
    if (rate = contract.event_rate_for_type(type))
      price = terms.key?("amount") ? terms["amount"].to_f : rate["amount"].to_f
      rate["unit"] == "hourly" ? (price * (hours || 1)).round(2) : price
    elsif contract.per_event_deal?
      terms.key?("amount") ? terms["amount"].to_f : contract.usual_date_term(type).to_f
    end
  end

  def cost_words(contract, type, terms, fixed)
    return number_to_currency(fixed) if fixed

    case contract.date_term_field(type)
    when :share
      "#{(terms['share'] || contract.usual_date_term(type)).to_f.then { |n| n % 1 == 0 ? n.to_i : n }}% of sales"
    when :amount
      "#{number_to_currency(terms.key?('amount') ? terms['amount'] : contract.usual_date_term(type))} fee"
    else
      "—"
    end
  end
end

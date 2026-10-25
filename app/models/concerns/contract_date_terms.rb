# frozen_string_literal: true

# Each contracted date's own terms (Review the dates, 2026-10-16): the deal
# sets what every date gets, and one date can differ, down to $0 ("free" is
# just a price of $0; there's no separate idea of it). What can change for a
# date depends on the deal:
#
#   a rehearsal (any kind with its own rate)  the rate for that date     :amount
#   a per-event fee                           that date's fee            :amount
#   tickets minus our fee, priced per show    our fee for that show      :amount
#   a revenue share                           our share of that show, %  :share
#   a flat fee for the whole contract         nothing (one amount)       nil
#
# Before activation the changes live in draft_payment_config["date_terms"],
# keyed by the booking's starts_at; activation stamps them onto each show
# (shows.contract_terms), where billing and settlement read them, so a moved
# date keeps its terms. An optional note shows beside the date.
module ContractDateTerms
  extend ActiveSupport::Concern

  # :amount, :share, or nil when the date has nothing to change by itself.
  def date_term_field(event_type)
    return :amount if separately_rated_event_types.include?(event_type)
    return :amount if per_event_deal?
    return nil if EventTypes.non_revenue_event_types.include?(event_type)
    return :share if revenue_share?
    return :amount if ticket_revenue_minus_fee? && flat_fee_basis == "per_show"

    nil
  end

  # What the deal gives this kind of date: dollars for :amount, percent for
  # :share, nil when there's nothing per date.
  def usual_date_term(event_type)
    if (rate = event_rate_for_type(event_type))
      rate["amount"].to_f
    elsif per_event_deal?
      draft_payment_config["per_event_amount"].to_f
    elsif date_term_field(event_type) == :share
      revenue_share_percentage.to_f
    elsif date_term_field(event_type) == :amount
      flat_fee_amount
    end
  end

  def per_event_deal?
    draft_payment_structure == "per_event"
  end

  def event_rate_for_type(event_type)
    draft_event_rates.find { |r| r["event_type"] == event_type && r["amount"].to_f.positive? }
  end

  # { booking starts_at => { "amount" | "share" => Float, "note" => String } }
  def draft_date_terms
    Hash(draft_payment_config["date_terms"])
  end

  def date_terms_for_booking(starts_at)
    draft_date_terms[starts_at.to_s] || {}
  end

  # Set or clear the terms of these bookings' dates (drafts only; an active
  # contract's dates change through "Change the deal"). A value equal to the
  # deal's, or blank, goes back to the deal; the note stays either way.
  def set_draft_date_terms!(starts_ats, value:, note:, field:)
    terms = next_date_terms(starts_ats, value: value, note: note, field: field)
    update_draft_step(:payment_config, draft_payment_config.merge("date_terms" => terms))
  end

  # The date terms with these dates changed, read against this contract's own
  # bookings and deal (a stand-in's, in an amendment). Saves nothing.
  def next_date_terms(starts_ats, value:, note:, field:)
    terms = draft_date_terms.dup
    bookings = draft_bookings.index_by { |b| b["starts_at"].to_s }
    Array(starts_ats).map(&:to_s).each do |starts_at|
      booking = bookings[starts_at]
      next unless booking && date_term_field(booking["event_type"] || "show") == field

      entry = (terms[starts_at] || {}).except("amount", "share")
      usual = usual_date_term(booking["event_type"] || "show")
      number = value.to_s.delete("$,%").presence&.to_f
      entry[field.to_s] = number.round(2) if number && number != usual
      entry["note"] = note.to_s.strip.presence
      entry.compact!
      entry.empty? ? terms.delete(starts_at) : terms[starts_at] = entry
    end
    terms
  end

  # --- Changing the deal on an active contract -----------------------------
  #
  # "Change the deal" has its own Review the dates. It reads a stand-in: the
  # deal as amended so far, the dates as they'll be, and each date's terms (as
  # staged in amend_data["date_terms"], or the shows' own to start with).

  def amend_terms_view(bookings)
    amend = amend_data
    terms = amend.key?("date_terms") ? Hash(amend["date_terms"]) : live_date_terms(bookings)
    Contract.new(organization: organization, contractor_name: contractor_name, production_name: production_name, draft_data: {
      "bookings" => bookings,
      "payment_structure" => amend["payment_structure"].presence || draft_payment_structure,
      "payment_config" => (amend["payment_config"].presence || draft_payment_config).merge("date_terms" => terms),
      "payments" => amend["payments"] || draft_payments,
      "production" => draft_data["production"]
    })
  end

  # { booking starts_at => terms } from this contract's shows, for the dates
  # among these bookings.
  def live_date_terms(bookings)
    shows = Show.where(space_rental_id: space_rentals.select(:id)).where("shows.contract_terms <> '{}'::jsonb").includes(:space_rental)
    by_time = shows.each_with_object({}) { |show, h| h[show.space_rental.starts_at.to_i] = show.contract_terms }
    Array(bookings).each_with_object({}) do |booking, h|
      at = parse_term_time(booking["starts_at"])
      h[booking["starts_at"].to_s] = by_time[at.to_i] if at && by_time.key?(at.to_i)
    end
  end

  # Applying the amendment: each existing date's show takes its terms (before
  # any date moves, so a moved night keeps them); the nights the amendment adds
  # take theirs once they exist. Dates with no entry go back to the deal.
  def stamp_amended_date_terms!(date_terms, rentals)
    by_time = Hash(date_terms).each_with_object({}) do |(starts_at, terms), h|
      at = parse_term_time(starts_at)
      h[at.to_i] = terms if at
    end
    Array(rentals).each do |rental|
      Show.where(space_rental_id: rental.id).update_all(contract_terms: by_time[rental.starts_at.to_i] || {}, updated_at: Time.current)
    end
  end

  # The amended payments with each show's own terms: a per-event deal's date
  # at its own fee, a show's own share in its settlement's words.
  def apply_show_terms_to_payments(payments)
    return payments unless per_event_deal? || revenue_share?

    shows = Show.where(space_rental_id: space_rentals.select(:id)).includes(:space_rental).to_a
    own, shares = {}, {}
    shows.each do |show|
      date = show.space_rental.starts_at.to_date
      own[date] = show.contract_terms["amount"].to_f if show.contract_terms.key?("amount")
      shares[date] = show.contract_terms["share"].to_f if show.contract_terms.key?("share")
    end
    apply_date_terms_to_draft_payments(payments, own: own, count: shows.size, shares: shares)
  end

  # The payments to bill: the deal's own list (draft_payments, as Financials
  # made it, never rewritten, so a date set to $0 and back gets its payment
  # back) with each date's own fee on a per-event deal. A $0 date has no
  # payment; one upfront payment for every date adds the dates up.
  def billed_draft_payments
    apply_date_terms_to_draft_payments(draft_payments)
  end

  # own: { Date => that date's fee }, shares: { Date => our share }, from
  # the draft's dates unless given.
  def apply_date_terms_to_draft_payments(payments, own: nil, count: nil, shares: nil)
    shares ||= draft_bookings.each_with_object({}) do |booking, h|
      terms = date_terms_for_booking(booking["starts_at"])
      date = parse_term_date(booking["starts_at"])
      h[date] = terms["share"].to_f if date && terms.key?("share")
    end
    payments = relabel_share_payments(payments, shares)
    return payments unless per_event_deal?

    own ||= draft_bookings.each_with_object({}) do |booking, h|
      terms = date_terms_for_booking(booking["starts_at"])
      date = parse_term_date(booking["starts_at"])
      h[date] = terms["amount"].to_f if date && terms.key?("amount")
    end
    return payments if own.empty?

    count ||= draft_bookings.size
    upfront = draft_payment_config["per_event_timing"] == "upfront"
    Array(payments).filter_map do |payment|
      next payment if payment["extra"]

      if upfront
        next payment unless payment["source"] == "Per event" && count.positive?

        each = payment["amount"].to_f / count
        total = (payment["amount"].to_f - own.values.sum { |amount| each - amount }).round(2)
        next total.positive? ? payment.merge("amount" => total, "description" => "#{count} events, paid upfront") : nil
      end

      # Each date's payment says which date it's for; older ones are due on it.
      date = parse_term_date(payment["event_date"]) || parse_term_date(payment["due_date"])
      next payment unless own.key?(date)

      own[date].positive? ? payment.merge("amount" => own[date]) : nil
    end
  end

  # --- After activation: each show's terms --------------------------------

  def terms_for(show)
    Hash(show&.contract_terms)
  end

  # Our share of this show's ticket sales, in percent.
  def our_share_for(show)
    share = terms_for(show)["share"]
    share.nil? ? revenue_share_percentage.to_f : share.to_f
  end

  def their_share_for(show)
    100.0 - our_share_for(show)
  end

  # Our fee for one show on a per-show tickets-minus-fee deal.
  def fee_for_show(show)
    amount = terms_for(show)["amount"]
    amount.nil? ? flat_fee_per_show : amount.to_f
  end

  # A per-event deal's fee for this date.
  def per_event_amount_for(show)
    amount = terms_for(show)["amount"]
    amount.nil? ? draft_payment_config["per_event_amount"].to_f : amount.to_f
  end

  # The share this payment settles across these shows: theirs when we hold the
  # ticket money and pay them out, ours when they sell and pay us. Reads the
  # stored answer, not who_sells_tickets' legacy fallback, exactly as the
  # settlement always has.
  def settled_share_amount(shows)
    they_sell = draft_payment_config["who_sells_tickets"] == "contractor"
    shows.sum do |show|
      revenue = settled_revenue(show.show_financials)
      pct = they_sell ? our_share_for(show) : their_share_for(show)
      revenue * pct / 100.0
    end.round(2)
  end

  # "Revenue share" / "30% of ticket sales to us", and when this date differs,
  # "0% this show" with "Usually 30%". [line, sub, changed?]
  # A revenue share settled night by night says each night's share: "Mar 5 —
  # 100% to them" for a show that's 0% to us. (Weekly and monthly settlements
  # cover several nights, so they keep the deal's words.)
  def relabel_share_payments(payments, shares)
    settlement = draft_payment_config["revenue_settlement"].presence || "same_day"
    return payments unless revenue_share? && shares.any? && %w[same_day next_day].include?(settlement)

    offset = settlement == "next_day" ? 1 : 0
    Array(payments).map do |payment|
      next payment if payment["extra"] || payment["source"] != "Revenue share"

      date = parse_term_date(payment["due_date"])&.-(offset)
      next payment unless date && shares.key?(date)

      ours = shares[date]
      words = payment["description"].to_s.sub(/\d+(?:\.\d+)?% to (them|us)\z/) do
        Regexp.last_match(1) == "them" ? "#{number_for(100 - ours)}% to them" : "#{number_for(ours)}% to us"
      end
      payment.merge("description" => words)
    end
  end

  def parse_term_date(value)
    parse_term_time(value)&.to_date
  end

  def parse_term_time(value)
    return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def date_terms_words(event_type, terms)
    field = date_term_field(event_type)
    usual = usual_date_term(event_type)
    kind = (EventTypes.labels[event_type] || event_type.to_s.titleize).downcase
    money = ->(n) { ActionController::Base.helpers.number_to_currency(n, precision: (n.to_f % 1).zero? ? 0 : 2) }

    if (rate = event_rate_for_type(event_type))
      per = rate["unit"] == "hourly" ? "an hour" : "per #{kind}"
      return [ "#{money.(terms['amount'])} this #{kind}", "Usually #{money.(usual)} #{per}", true ] if terms.key?("amount")

      [ "#{money.(usual)} #{per}", nil, false ]
    elsif per_event_deal?
      return [ "#{money.(terms['amount'])} this date", "Usually #{money.(usual)} per event", true ] if terms.key?("amount")

      [ "#{money.(usual)} per event", nil, false ]
    elsif field == :share
      return [ "#{number_for(terms['share'])}% this show", "Usually #{number_for(usual)}% to us", true ] if terms.key?("share")

      [ "Revenue share", "#{number_for(usual)}% of ticket sales to us", false ]
    elsif field == :amount
      return [ "#{money.(terms['amount'])} fee this show", "Usually #{money.(usual)}", true ] if terms.key?("amount")

      [ "Ticket sales minus our fee", "#{money.(usual)} fee to us", false ]
    elsif ticket_revenue_minus_fee?
      [ "Ticket sales minus our fee", "Part of the #{money.(flat_fee_amount)} fee", false ]
    elsif EventTypes.non_revenue_event_types.include?(event_type)
      [ "Part of the deal", nil, false ]
    else
      [ "Flat fee", "Part of the #{money.(flat_fee_amount)} fee", false ]
    end
  end
end

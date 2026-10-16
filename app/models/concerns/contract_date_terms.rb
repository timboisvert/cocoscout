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
  # contract's dates change through the show). A value equal to the deal's,
  # or blank, goes back to the deal; the note stays either way.
  def set_draft_date_terms!(starts_ats, value:, note:, field:)
    terms = draft_date_terms
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
    update_draft_step(:payment_config, draft_payment_config.merge("date_terms" => terms))
    update_draft_step(:payments, apply_date_terms_to_draft_payments(draft_payments)) if per_event_deal?
  end

  # A per-event deal's draft payments are one per date, made on the Financials
  # page; a date with its own fee carries it, and a $0 date has none.
  def apply_date_terms_to_draft_payments(payments)
    return payments unless per_event_deal?

    by_date = draft_bookings.each_with_object({}) do |booking, h|
      terms = date_terms_for_booking(booking["starts_at"])
      date = (Time.zone.parse(booking["starts_at"].to_s)&.to_date rescue nil)
      h[date] = terms["amount"] if date && terms.key?("amount")
    end
    return payments if by_date.empty?

    Array(payments).filter_map do |payment|
      next payment if payment["extra"]

      date = (Date.parse(payment["due_date"].to_s) rescue nil)
      next payment unless by_date.key?(date)

      amount = by_date[date].to_f
      amount.positive? ? payment.merge("amount" => amount) : nil
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
      revenue = show.show_financials&.total_revenue.to_f
      pct = they_sell ? our_share_for(show) : their_share_for(show)
      revenue * pct / 100.0
    end.round(2)
  end

  # "Revenue share" / "30% of ticket sales to us", and when this date differs,
  # "0% this show" with "Usually 30%". [line, sub, changed?]
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

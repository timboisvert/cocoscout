# frozen_string_literal: true

# A revenue share's minimum guarantee (Tim, 2026-11-20): they take home at
# least a set amount, either per show or for the whole run.
#
#   per show      each date settles as the larger of their share that night
#                 and the minimum (#settled_share_amount)
#   for the run   the dates settle as their share alone; after the last date,
#                 if their shares came to less than the minimum, one payment
#                 named RUN_GUARANTEE makes up the difference
#                 (#run_guarantee_topup, ContractPaymentSyncService)
#
# Before 2026-11-20 the wizard saved the yes as "revenue_has_guarantee"
# and made one payment for the whole amount, due a week out, on top of the
# shares; no contract used it. A guarantee with no scope is read as per show.
module ContractRevenueGuarantee
  extend ActiveSupport::Concern

  RUN_GUARANTEE = "Minimum guarantee for the run"
  GUARANTEE_SCOPES = %w[per_show run].freeze

  def revenue_guarantee?
    return false unless revenue_share?

    cfg = draft_payment_config
    (cfg["revenue_has_guarantee"].to_s == "true" || cfg["revenue_guarantee"].to_s == "true") && revenue_guarantee_amount.positive?
  end

  def revenue_guarantee_amount
    draft_payment_config["revenue_guarantee_amount"].to_f
  end

  def revenue_guarantee_scope
    draft_payment_config["revenue_guarantee_scope"].presence_in(GUARANTEE_SCOPES) || "per_show"
  end

  def guarantee_per_show? = revenue_guarantee? && revenue_guarantee_scope == "per_show"
  def guarantee_for_run? = revenue_guarantee? && revenue_guarantee_scope == "run"

  # The one payment that tops up a whole-run guarantee.
  def run_guarantee_payment?(payment)
    payment.description.to_s == RUN_GUARANTEE
  end

  # One night's share settled under a per-show minimum. We hold the ticket
  # money: we hand them at least the minimum. They sell and pay us our share:
  # our share shrinks so they keep at least the minimum of their own sales,
  # never below nothing.
  def guaranteed_night_share(revenue, share, they_sell:)
    return share unless guarantee_per_show?

    minimum = revenue_guarantee_amount
    they_sell ? [ [ share, revenue - minimum ].min, 0.0 ].max : [ share, minimum ].max
  end

  # What they took home from one night before any whole-run top-up.
  def their_take_home(show)
    revenue = settled_revenue(show.show_financials)
    they_sell = draft_payment_config["who_sells_tickets"] == "contractor"
    share = settled_share_amount([ show ])
    they_sell ? (revenue - share) : share
  end

  # "$500" or "$512.50".
  def guarantee_money(amount = revenue_guarantee_amount)
    ActionController::Base.helpers.number_to_currency(amount, precision: amount.to_f % 1 == 0 ? 0 : 2)
  end

  # "at least $500 a show" / "at least $500 for the whole run", for list rows
  # and labels. Nil with no guarantee.
  def guarantee_short_words
    return nil unless revenue_guarantee?

    "at least #{guarantee_money} #{guarantee_for_run? ? 'for the whole run' : 'a show'}"
  end

  # The guarantee in full sentences, for the contract document, the review
  # step, and the contract's terms. Nil with no guarantee.
  def guarantee_sentences
    return nil unless revenue_guarantee?

    them = contractor_name.presence || "The producer"
    us = organization&.name.presence || "We"
    minimum = guarantee_money(revenue_guarantee_amount)
    if guarantee_for_run?
      "#{them} takes home at least #{minimum} for the whole run. If their shares across every date come to less, " \
        "#{us} pays them the difference after the last date."
    elsif draft_payment_config["who_sells_tickets"] == "contractor"
      "#{them} takes home at least #{minimum} a show. On any date where paying our share would leave them less, " \
        "our share for that date is reduced so they keep #{minimum}."
    else
      "#{them} takes home at least #{minimum} a show. On any date where their share of ticket sales comes to less, " \
        "#{us} pays them #{minimum} for that date."
    end
  end

  # What an amount still waiting on ticket sales is at least, or at most:
  # "At least $500" for a night under a per-show minimum (a week's or a
  # month's settlement: the minimum for each of its shows), "Up to $500" for
  # the whole run's top-up. Works on a payment or a draft payment's hash.
  def guarantee_amount_label(payment)
    return nil unless revenue_guarantee?

    description = payment.respond_to?(:description) ? payment.description.to_s : payment["description"].to_s
    tbd = payment.respond_to?(:amount_tbd?) ? payment.amount_tbd? : ActiveModel::Type::Boolean.new.cast(payment["amount_tbd"])
    direction = payment.respond_to?(:direction) ? payment.direction.to_s : payment["direction"].to_s
    return nil unless tbd

    if description == RUN_GUARANTEE
      "Up to #{guarantee_money}"
    elsif guarantee_per_show? && direction == "outgoing" && draft_payment_config["who_sells_tickets"] != "contractor"
      return "At least #{guarantee_money}" if payment.is_a?(ContractPayment) && payment.show_id.present? && !period_settlement?(payment)
      unless payment.is_a?(ContractPayment)
        return Contract::PER_NIGHT_CADENCES.include?(settlement_cadence) ? "At least #{guarantee_money}" : "At least #{guarantee_money} a show"
      end

      count = settlement_shows_for(payment).size
      count > 1 ? "At least #{guarantee_money(revenue_guarantee_amount * count)}" : "At least #{guarantee_money}"
    end
  end

  # The line under a payment that the guarantee shaped: what a night's
  # settlement was raised by, or where the whole run's top-up stands.
  def guarantee_payment_note(payment)
    return nil unless revenue_guarantee? && payment.is_a?(ContractPayment)

    if run_guarantee_payment?(payment)
      return payment.notes.presence if payment.status_cancelled? || !payment.amount_tbd?

      "Up to #{guarantee_money}. Worked out after the last date, once every date's sales are in."
    elsif guarantee_per_show? && !payment.amount_tbd? && settlement_payment?(payment)
      extra = guarantee_extra_for(settlement_shows_for(payment))
      "Includes #{guarantee_money(extra)} to bring it up to the #{guarantee_money} minimum a show." if extra.positive?
    end
  end

  # How much a per-show minimum added to these nights, beyond their share.
  def guarantee_extra_for(shows)
    return 0.0 unless guarantee_per_show?

    they_sell = draft_payment_config["who_sells_tickets"] == "contractor"
    shows.select { |show| show.show_financials&.has_data? }.sum do |show|
      revenue = settled_revenue(show.show_financials)
      pct = they_sell ? our_share_for(show) : their_share_for(show)
      share = revenue * pct / 100.0
      (guaranteed_night_share(revenue, share, they_sell: they_sell) - share).abs
    end.round(2)
  end

  # The whole run's top-up payment, if there is one.
  def run_guarantee_payment
    contract_payments.find_by(description: RUN_GUARANTEE)
  end

  # Keep the whole run's top-up on the run's last show, due the day after it,
  # so Settle up meets it on the last night and dates moved by an amendment
  # move it too. Never once paid or on a payout run.
  def link_run_guarantee!
    payment = run_guarantee_payment
    return unless payment
    return if payment.status_paid? || payment.in_payout_run?

    last = money_shows.select { |show| show.date_and_time.present? }.max_by(&:date_and_time)
    return unless last

    attrs = { show_id: last.id, due_date: last.date_and_time.to_date + 1 }
    payment.update!(attrs) if attrs.any? { |key, value| payment.public_send(key) != value }
  end

  # Once every date has its sales in, the top-up is the minimum less what
  # their shares came to. Nothing short: it closes, saying so. A date's sales
  # withdrawn: it waits again. Never rewritten once paid or on a payout run.
  # Run after each night's sales (ContractPaymentSyncService) and after an
  # amendment, which can move the dates or rewrite the row.
  def settle_run_guarantee!
    return unless guarantee_for_run?

    payment = run_guarantee_payment
    return unless payment
    return if payment.status_paid? || payment.in_payout_run?

    link_run_guarantee!
    payment.reload
    result = run_guarantee_topup
    reopened = payment.status_cancelled? ? "pending" : payment.status
    if result.nil?
      payment.update!(amount: 0, amount_tbd: true, status: reopened, notes: "Worked out once every date's sales are in.")
    elsif result[:topup].positive?
      payment.update!(amount: result[:topup], amount_tbd: false, status: reopened,
                      notes: "Their shares came to #{guarantee_cents_words(result[:taken])}, " \
                             "#{guarantee_cents_words(result[:topup])} under the #{guarantee_cents_words(revenue_guarantee_amount)} minimum.")
    else
      payment.update!(amount: 0, amount_tbd: false, status: "cancelled",
                      notes: "Their shares came to #{guarantee_cents_words(result[:taken])}, at or over the " \
                             "#{guarantee_cents_words(revenue_guarantee_amount)} minimum, so nothing is owed.")
    end
  end

  def guarantee_cents_words(amount)
    ActionController::Base.helpers.number_to_currency(amount)
  end

  # What the whole-run top-up comes to once every date has its sales in: the
  # minimum less what their shares came to, never below nothing. Nil while a
  # date is still waiting on its sales, or when there's no whole-run minimum.
  def run_guarantee_topup
    return nil unless guarantee_for_run?

    shows = money_shows.to_a
    return nil if shows.empty? || shows.any? { |show| !show.show_financials&.has_data? }

    taken = shows.sum { |show| their_take_home(show) }.round(2)
    { taken: taken, topup: [ (revenue_guarantee_amount - taken).round(2), 0.0 ].max }
  end
end

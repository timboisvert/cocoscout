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

# frozen_string_literal: true

# Syncs show-level financial data to ContractPayment records for revenue-share
# and ticket-revenue-minus-fee contracts.
#
# When a show's financials are confirmed for a third-party production,
# this service finds the matching ContractPayment (by settlement period)
# and updates it with the calculated contractor share.
class ContractPaymentSyncService
  def initialize(show)
    @show = show
    @production = show.production
    # The contract that applies to THIS show is the one that booked its space rental
    # (a production can carry several contracts). Fall back to the production's latest.
    @contract = show.space_rental&.contract || @production&.contract
  end

  def call
    return unless should_sync?

    # Both bases answer the same question — how often do we settle — so they
    # share one dispatch. Only a minus-fee deal can settle "once".
    case @contract.settlement_cadence
    when "once"
      sync_whole_contract
    when "per_event", "next_day", "same_day"
      sync_per_event
    when "weekly"
      sync_period(:beginning_of_week)
    else # monthly
      sync_period(:beginning_of_month)
    end
  end

  private

  def should_sync?
    # Driven by the CONTRACT, not the production's type flag: any show governed by
    # a revenue-share (or revenue-minus-fee) contract settles its share this way,
    # even if it's linked to an in-house production rather than a third-party one.
    @contract&.revenue_share? || @contract&.ticket_revenue_minus_fee?
  end

  # Case 3 settling once: we sell, contractor gets all ticket revenue minus our
  # fee. One whole-contract payment settled from every confirmed show.
  def sync_whole_contract
    summary = @contract.flat_fee_revenue_summary
    return unless summary

    payment = @contract.settlement_payments.first
    return unless payment

    confirmed = @contract.contract_shows.includes(:show_financials)
                         .select { |s| s.show_financials&.has_data? }

    if summary[:confirmed_count].positive?
      settle(payment, confirmed, pending_count: summary[:pending_count])
    else
      reset_to_tbd(payment)
    end
  end

  # For per-event settlement: each show maps to one ContractPayment
  def sync_per_event
    payment = @contract.find_payment_for_show(@show)
    return unless payment

    if @show.show_financials&.has_data?
      settle(payment, [ @show ])
    else
      reset_to_tbd(payment)
    end
  end

  # For weekly/monthly settlement: aggregate all shows in the period
  def sync_period(period_method)
    # Find all settlement payments. Direction-agnostic: a revenue split can run
    # either way, and a minus-fee settlement flips to face whichever way the
    # money went.
    revenue_payments = @contract.settlement_payments

    # Group shows by period
    all_shows = @contract.contract_shows.includes(:show_financials).to_a

    revenue_payments.each do |payment|
      period_start = payment.due_date.public_send(period_method)
      period_shows = all_shows.select { |s| s.date_and_time.to_date.public_send(period_method) == period_start }

      confirmed_shows = period_shows.select { |s| s.show_financials&.has_data? }

      if confirmed_shows.any?
        settle(payment, confirmed_shows, pending_count: period_shows.size - confirmed_shows.size)
      elsif settlement_payment?(payment)
        # All shows still pending — keep TBD
        reset_to_tbd(payment)
      end
    end
  end

  # Bring one settlement in line with the shows it covers: its amount, and on
  # a minus-fee deal which way it faces.
  def settle(payment, shows, pending_count: 0)
    show_details = shows.map { |s| [ s, s.show_financials.total_revenue ] }
    remainder = settled_amount_for(shows)
    update_payment(payment, remainder.abs, show_details, pending_count: pending_count)
    face_the_money!(payment, remainder, shows)
  end

  # Financials withdrawn (or none in yet): the settlement is TBD again, and a
  # minus-fee one faces its natural way while it waits.
  def reset_to_tbd(payment)
    return if payment.status_paid? || payment.in_payout_run?

    attrs = { amount: 0, amount_tbd: true }
    if @contract.ticket_revenue_minus_fee? && payment.auto_shortfall?
      attrs.merge!(direction: "outgoing", auto_shortfall: false,
                   description: settlement_description(period_label_for(payment)))
    end
    payment.update!(attrs)
  end

  # What one settlement covering these shows should move. A minus-fee deal
  # hands back their revenue less the fee for exactly the shows in this
  # settlement — so a week of three shows deducts three shows' worth, and the
  # run as a whole still deducts the whole fee. A split takes its percentage.
  #
  # For a minus-fee deal the number is SIGNED: negative means the night took
  # less than our fee, so the difference is money they owe us (see
  # #face_the_money!). A split is always positive.
  def settled_amount_for(shows)
    if @contract.ticket_revenue_minus_fee?
      @contract.settlement_remainder(shows)
    else
      revenue = shows.sum { |s| s.show_financials.total_revenue }
      (revenue * share_pct_for(nil) / 100.0).round(2)
    end
  end

  # A minus-fee deal has exactly one settlement per show (or period), and it
  # faces whichever way the money actually goes. Revenue above the fee: we hand
  # them the remainder — an outgoing payment. Revenue under the fee: our fee
  # still stands, their tickets covered what they covered, and they owe us the
  # rest — the same payment, now incoming and collectable. Never a second row,
  # and never a payment that's already gone through or joined a run.
  def face_the_money!(payment, remainder, shows)
    return unless @contract.ticket_revenue_minus_fee?
    return if payment.status_paid? || payment.in_payout_run?

    label = period_label_for(payment, shows)
    if remainder.negative?
      revenue = shows.sum { |s| s.show_financials.total_revenue }
      fee = @contract.flat_fee_for_shows(shows.size)
      money = ActionController::Base.helpers.method(:number_to_currency)
      payment.update!(
        direction: "incoming", auto_shortfall: true, settlement_method: "direct",
        description: "Fee shortfall — #{label}",
        notes: "Ticket revenue of #{money.call(revenue)} came in " \
               "#{money.call(-remainder)} under our #{money.call(fee)} fee."
      )
    elsif payment.direction_incoming? && payment.auto_shortfall?
      # Revenue caught back up — the settlement faces them again.
      payment.update!(direction: "outgoing", auto_shortfall: false,
                      description: settlement_description(label))
    end
  end

  def settlement_description(label)
    fee = ActionController::Base.helpers.number_to_currency(@contract.flat_fee_per_show)
    base = "Ticket revenue less #{fee} fee"
    @contract.settles_periodically? && label ? "#{base} — #{label}" : base
  end

  # How the settlement names its stretch of dates: a single night by its date,
  # a period by its first and last.
  def period_label_for(payment, shows = nil)
    dates = Array(shows).filter_map(&:date_and_time).sort
    dates = [ payment.due_date ] if dates.empty? && @contract.settles_periodically?
    return nil if dates.empty?
    return dates.first.strftime("%b %-d") if dates.first.to_date == dates.last.to_date

    "#{dates.first.strftime('%b %-d')}–#{dates.last.strftime('%b %-d')}"
  end

  # Whether a payment is one of the contract's core settlements (as opposed to
  # a one-off added by hand), so we only ever reset those back to TBD.
  def settlement_payment?(payment)
    @contract.ticket_revenue_minus_fee? || payment.revenue_share?
  end

  # The slice of ticket revenue this payment settles. When the contractor sells
  # their own tickets (Case 2, v2 config), they hold the money and owe us our
  # cut, so the payment settles OUR share. Otherwise we hold the money and owe
  # them theirs (Case 1), so it settles the contractor's share.
  def share_pct_for(_payment)
    if @contract.draft_payment_config["who_sells_tickets"] == "contractor"
      @contract.revenue_share_percentage
    else
      @contract.contractor_share_percentage
    end
  end

  def update_payment(payment, amount, show_details, pending_count: 0)
    # Never rewrite a payment that's already been settled. A re-sync (e.g. a
    # contractor re-submitting sales on a closed contract) must not overwrite the
    # amount/notes of money that already moved. Same for one that's joined a
    # payout run: the run's contribution is fixed by the transfer.
    return if payment.status_paid? || payment.in_payout_run?

    attrs = { amount: amount }

    # Only clear TBD if all shows in the period are confirmed
    attrs[:amount_tbd] = pending_count > 0

    # Build descriptive notes
    show_lines = show_details.map { |show, rev| "#{show.display_name} (#{show.date_and_time.strftime('%b %-d')}): #{ActionController::Base.helpers.number_to_currency(rev)}" }
    notes_parts = [ "Auto-calculated from show financials:", *show_lines ]
    notes_parts << "#{pending_count} show(s) still pending" if pending_count > 0
    attrs[:notes] = notes_parts.join("\n")

    payment.update!(attrs)
  end
end

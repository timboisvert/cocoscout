# frozen_string_literal: true

# Syncs show-level financial data to ContractPayment records for revenue-share contracts.
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
  # fee. One whole-contract outgoing payment settled from every confirmed show.
  def sync_whole_contract
    summary = @contract.flat_fee_revenue_summary
    return unless summary

    payment = @contract.contract_payments.where(direction: "outgoing").order(:due_date).first
    return unless payment

    confirmed = @contract.contract_shows.includes(:show_financials)
                         .select { |s| s.show_financials&.has_data? }

    if summary[:confirmed_count].positive?
      details = confirmed.map { |s| [ s, s.show_financials.total_revenue ] }
      update_payment(payment, summary[:contractor_share], details, pending_count: summary[:pending_count])
      sync_shortfall(payment, confirmed)
    elsif !payment.status_paid?
      payment.update(amount: 0, amount_tbd: true)
      clear_shortfall(payment)
    end
  end

  # What one settlement covering these shows should move. A minus-fee deal
  # hands back their revenue less the fee for exactly the shows in this
  # settlement — so a week of three shows deducts three shows' worth, and the
  # run as a whole still deducts the whole fee. A split takes its percentage.
  #
  # Never negative: when the fee comes to more than the night took, there is
  # nothing to hand back and the difference becomes money they owe us instead
  # (see #sync_shortfall).
  def settled_amount_for(shows)
    if @contract.ticket_revenue_minus_fee?
      [ @contract.settlement_remainder(shows), 0 ].max
    else
      revenue = shows.sum { |s| s.show_financials.total_revenue }
      (revenue * share_pct_for(nil) / 100.0).round(2)
    end
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

  # For per-event settlement: each show maps to one ContractPayment
  def sync_per_event
    payment = @contract.find_payment_for_show(@show)
    return unless payment

    financials = @show.show_financials
    if financials&.has_data?
      update_payment(payment, settled_amount_for([ @show ]), [ [ @show, financials.total_revenue ] ])
      sync_shortfall(payment, [ @show ])
    elsif !payment.status_paid?
      # Reset to TBD if financial data removed
      payment.update(amount: 0, amount_tbd: true) if payment.amount_tbd? == false
      clear_shortfall(payment)
    end
  end

  # For weekly/monthly settlement: aggregate all shows in the period
  def sync_period(period_method)
    # Find all settlement payments. Direction-agnostic: a revenue split can run
    # either way, while minus-fee settlements are always outgoing.
    revenue_payments = @contract.settlement_payments

    # Group shows by period
    all_shows = @contract.contract_shows.includes(:show_financials).to_a

    revenue_payments.each do |payment|
      period_start = payment.due_date.public_send(period_method)
      period_shows = all_shows.select { |s| s.date_and_time.to_date.public_send(period_method) == period_start }

      confirmed_shows = period_shows.select { |s| s.show_financials&.has_data? }

      if confirmed_shows.any?
        show_details = confirmed_shows.map { |s| [ s, s.show_financials.total_revenue ] }
        update_payment(payment, settled_amount_for(confirmed_shows), show_details,
                       pending_count: period_shows.size - confirmed_shows.size)
        sync_shortfall(payment, confirmed_shows)
      elsif settlement_payment?(payment) && !payment.status_paid?
        # All shows still pending — keep TBD
        payment.update(amount: 0, amount_tbd: true)
        clear_shortfall(payment)
      end
    end
  end

  # --- Fee shortfalls ---------------------------------------------------------
  # A minus-fee deal assumes the night takes more than our fee, so what's left
  # goes back to them. When it doesn't, the fee still stands: their ticket
  # revenue covers what it covers and they owe us the rest. That difference
  # rides alongside the settlement as an ordinary incoming payment, so it can be
  # collected with a pay link or recorded when the money arrives some other way.
  def sync_shortfall(settlement, shows)
    return unless @contract.ticket_revenue_minus_fee?
    # A settlement that's already gone through is closed — whatever it settled
    # for, it settled. Restating the revenue behind it doesn't reopen a bill.
    return if settlement.status_paid?

    owed = -@contract.settlement_remainder(shows)
    return clear_shortfall(settlement) unless owed.positive?

    existing = shortfall_payment_for(settlement)
    # Money that already changed hands is never rewritten, here as anywhere.
    return if existing&.status_paid?

    revenue = shows.sum { |s| s.show_financials&.total_revenue.to_f }
    fee = @contract.flat_fee_for_shows(shows.size)
    money = ActionController::Base.helpers.method(:number_to_currency)
    attrs = {
      amount: owed,
      amount_tbd: false,
      due_date: settlement.due_date,
      show_id: settlement.show_id,
      description: "Fee shortfall — #{shortfall_period_label(shows)}",
      notes: "Ticket revenue of #{money.call(revenue)} came in " \
             "#{money.call(owed)} under our #{money.call(fee)} fee."
    }

    if existing
      existing.update!(attrs)
    else
      @contract.contract_payments.create!(
        attrs.merge(direction: "incoming", status: "pending",
                    settlement_method: "direct", auto_shortfall: true)
      )
    end
  end

  # Revenue caught up (or the numbers were withdrawn) — nothing is owed, so the
  # row goes away. One that's been paid stays: that money really moved.
  def clear_shortfall(settlement)
    payment = shortfall_payment_for(settlement)
    payment.destroy if payment && !payment.status_paid?
  end

  # This settlement's shortfall row, if it has one. Per-event settlements carry
  # a show; period ones are found by the date they settle on.
  def shortfall_payment_for(settlement)
    rows = @contract.contract_payments.where(auto_shortfall: true).order(:id).to_a
    return rows.find { |p| p.show_id == settlement.show_id } if settlement.show_id.present?

    rows.find { |p| p.show_id.nil? && p.due_date == settlement.due_date } ||
      (@contract.settles_periodically? ? nil : rows.find { |p| p.show_id.nil? })
  end

  def shortfall_period_label(shows)
    dates = shows.filter_map(&:date_and_time).sort
    return "this settlement" if dates.empty?
    return dates.first.strftime("%b %-d") if dates.first.to_date == dates.last.to_date

    "#{dates.first.strftime('%b %-d')}–#{dates.last.strftime('%b %-d')}"
  end

  def update_payment(payment, amount, show_details, pending_count: 0)
    # Never rewrite a payment that's already been settled. A re-sync (e.g. a
    # contractor re-submitting sales on a closed contract) must not overwrite the
    # amount/notes of money that already moved.
    return if payment.status_paid?

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

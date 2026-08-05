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

    if summary[:confirmed_count].positive?
      details = @contract.contract_shows.includes(:show_financials)
                         .select { |s| s.show_financials&.has_data? }
                         .map { |s| [ s, s.show_financials.total_revenue ] }
      update_payment(payment, summary[:contractor_share], details, pending_count: summary[:pending_count])
    elsif !payment.status_paid?
      payment.update(amount: 0, amount_tbd: true)
    end
  end

  # What one settlement covering these shows should move. A minus-fee deal
  # hands back their revenue less the fee for exactly the shows in this
  # settlement — so a week of three shows deducts three shows' worth, and the
  # run as a whole still deducts the whole fee. A split takes its percentage.
  def settled_amount_for(shows)
    revenue = shows.sum { |s| s.show_financials.total_revenue }

    if @contract.ticket_revenue_minus_fee?
      [ (revenue - @contract.flat_fee_for_shows(shows.size)).round(2), 0 ].max
    else
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
    elsif !payment.status_paid?
      # Reset to TBD if financial data removed
      payment.update(amount: 0, amount_tbd: true) if payment.amount_tbd? == false
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
      elsif settlement_payment?(payment) && !payment.status_paid?
        # All shows still pending — keep TBD
        payment.update(amount: 0, amount_tbd: true)
      end
    end
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

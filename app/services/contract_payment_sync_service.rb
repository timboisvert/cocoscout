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
    @contract = @production&.contract
  end

  def call
    return unless should_sync?

    settlement = @contract.draft_payment_config["revenue_settlement"] || "monthly"

    case settlement
    when "per_event", "next_day"
      sync_per_event
    when "weekly"
      sync_period(:beginning_of_week)
    else # monthly
      sync_period(:beginning_of_month)
    end
  end

  private

  def should_sync?
    @contract&.revenue_share? && @production&.type_third_party?
  end

  def contractor_share_pct
    @contract.contractor_share_percentage
  end

  # For per-event settlement: each show maps to one ContractPayment
  def sync_per_event
    payment = @contract.find_payment_for_show(@show)
    return unless payment

    financials = @show.show_financials
    if financials&.has_data?
      contractor_amount = (financials.total_revenue * contractor_share_pct / 100.0).round(2)
      update_payment(payment, contractor_amount, [ [ @show, financials.total_revenue ] ])
    else
      # Reset to TBD if financial data removed
      payment.update(amount: 0, amount_tbd: true) if payment.amount_tbd? == false
    end
  end

  # For weekly/monthly settlement: aggregate all shows in the period
  def sync_period(period_method)
    # Find all revenue-share payments
    revenue_payments = @contract.contract_payments
                                .where(direction: "incoming")
                                .where("description LIKE ? OR amount_tbd = ?", "%Revenue Share%", true)
                                .order(:due_date)

    # Group shows by period
    all_shows = @contract.productions
                         .flat_map { |p| p.shows.includes(:show_financials).to_a }

    revenue_payments.each do |payment|
      period_start = payment.due_date.public_send(period_method)
      period_shows = all_shows.select { |s| s.date_and_time.to_date.public_send(period_method) == period_start }

      confirmed_shows = period_shows.select { |s| s.show_financials&.has_data? }

      if confirmed_shows.any?
        total_revenue = confirmed_shows.sum { |s| s.show_financials.total_revenue }
        contractor_amount = (total_revenue * contractor_share_pct / 100.0).round(2)
        show_details = confirmed_shows.map { |s| [ s, s.show_financials.total_revenue ] }
        update_payment(payment, contractor_amount, show_details, pending_count: period_shows.size - confirmed_shows.size)
      elsif payment.revenue_share?
        # All shows still pending — keep TBD
        payment.update(amount: 0, amount_tbd: true)
      end
    end
  end

  def update_payment(payment, amount, show_details, pending_count: 0)
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

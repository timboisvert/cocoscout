# frozen_string_literal: true

module Manage
  # The theater's CocoScout balance (see TicketBalance): what's waiting on
  # upcoming shows, what's settling, what's spendable — and withdrawing it to
  # the theater's bank, by hand or automatically.
  class TicketBalanceController < Manage::TicketingBaseController
    def show
      @summary = TicketBalance.summary(Current.organization)
      @obligations = BalanceObligations.items(Current.organization)
      @safe_cents = [ @summary.available_cents - @obligations.sum(&:cents), 0 ].max
      @top_ups = Current.organization.balance_top_ups.order(created_at: :desc).limit(10)
      @withdrawals = Current.organization.balance_withdrawals.order(created_at: :desc).limit(20).includes(:requested_by)
      @upcoming = upcoming_by_show
    end

    def withdraw
      cents = (BigDecimal(params[:amount].to_s.delete(",$ ").presence || "0") * 100).round
      withdrawal = BalanceWithdrawalService.withdraw!(Current.organization, amount_cents: cents, by: Current.user)
      redirect_to manage_ticket_balance_path,
                  notice: "#{helpers.number_to_currency(withdrawal.amount_cents / 100.0)} is on its way to your bank."
    rescue ArgumentError
      redirect_to manage_ticket_balance_path, alert: "Enter an amount like 250.00."
    rescue BalanceWithdrawalService::Error => e
      redirect_to manage_ticket_balance_path, alert: e.message
    end

    # Money added from the bank or card the theater funds payout runs with.
    def top_up
      cents = (BigDecimal(params[:amount].to_s.delete(",$ ").presence || "0") * 100).round
      top_up = BalanceTopUpService.start!(Current.organization, amount_cents: cents, by: Current.user)
      notice = if top_up.status == "succeeded"
        "#{helpers.number_to_currency(top_up.amount_cents / 100.0)} added to your balance."
      else
        "Adding #{helpers.number_to_currency(top_up.amount_cents / 100.0)} from your bank. It lands in 2 to 4 business days."
      end
      redirect_to manage_ticket_balance_path, notice: notice
    rescue ArgumentError
      redirect_to manage_ticket_balance_path, alert: "Enter an amount like 250.00."
    rescue BalanceTopUpService::Error => e
      redirect_to manage_ticket_balance_path, alert: e.message
    end

    def update_auto_withdraw
      choice = params[:auto_withdraw].presence_in(TicketingProfile::AUTO_WITHDRAW) || "off"
      ticketing_profile.update!(auto_withdraw: choice)
      redirect_to manage_ticket_balance_path, notice: choice == "off" ? "Automatic withdrawal is off." : "Automatic withdrawal is on."
    end

    private

    # Upcoming shows and what each holds for the theater: what it sold
    # through CocoScout, less what it refunded.
    def upcoming_by_show
      Current.organization.ticket_listings.where(released_at: nil).where.not(status: "canceled")
             .joins(:show).where(shows: { canceled: false })
             .includes(:show).order("shows.date_and_time").limit(30)
             .map { |listing| [ listing, held_for(listing) ] }
             .select { |_, cents| cents.positive? }
    end

    def held_for(listing)
      orders = listing.ticket_orders.where(money_path: "cocoscout", status: TicketOrder::WAS_PAID)
      orders.sum(:org_net_cents) - TicketRefund.succeeded.where(ticket_order_id: orders.select(:id)).sum(:org_debit_cents) -
        TicketExchange.where(from_order_id: orders.select(:id)).sum(:moved_cents)
    end
  end
end

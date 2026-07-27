# frozen_string_literal: true

module Manage
  # Money → Incoming: the receivables side of the Money hub, mirroring Payouts.
  # Where Payouts tracks money the org owes performers, this tracks money owed TO
  # the org — almost entirely incoming contract payments (rental fees, deposits).
  #
  # There is no "run" concept here: incoming money is collected one payment at a
  # time (a Stripe pay link, an in-person QR code, or recorded by hand when it
  # arrives offline), so the depth is index → per-production list → payment detail.
  class MoneyIncomingController < Manage::ManageController
    include ActionView::Helpers::NumberHelper

    # Forward-looking windows for the "what's coming in" view.
    WINDOWS = [
      { key: "1m",  label: "30 days",   months: 1 },
      { key: "3m",  label: "3 months",  months: 3 },
      { key: "6m",  label: "6 months",  months: 6 },
      { key: "12m", label: "12 months", months: 12 },
      { key: "all", label: "All",       months: nil }
    ].freeze

    before_action :set_production, only: :index

    # Org-wide list grouped by production (mirrors money_payouts#index), or a
    # single production's incoming payments when a production_id is present.
    # A forward window (?window=) focuses the list + forecast on money expected
    # in the next N months; overdue money always shows regardless of window.
    def index
      @windows = WINDOWS
      window = WINDOWS.find { |w| w[:key] == params[:window] } || WINDOWS.find { |w| w[:key] == "3m" }
      @window_key = window[:key]
      @window_label = window[:label]
      @window_end = window[:months] ? (Date.current >> window[:months]) : nil

      scope = incoming_scope.includes(contract: [ :contractor, :production ])
      scope = scope.where(contracts: { production_id: @production.id }) if @production
      all_pending = scope.by_due_date.to_a

      # Grand totals — everything still owed, independent of the window.
      @total_outstanding = all_pending.sum { |p| p.amount.to_f }
      overdue_all = all_pending.select(&:overdue?)
      @overdue_count = overdue_all.size
      @total_overdue = overdue_all.sum { |p| p.amount.to_f }

      # Windowed set for the list + breakdown: overdue (always) + due within window.
      @payments = if @window_end
                    all_pending.select { |p| p.overdue? || p.due_date <= @window_end }
      else
                    all_pending
      end

      # Forecast: upcoming (not overdue) money, bucketed by month.
      upcoming = @payments.reject(&:overdue?)
      @upcoming_count = upcoming.size
      @expected_in_window = upcoming.reject(&:amount_tbd?).sum { |p| p.amount.to_f }
      @monthly_forecast = build_monthly_forecast(upcoming, @window_end)

      unless @production
        with_production, @orphan_payments = @payments.partition { |p| p.contract.production_id.present? }
        @production_summaries = with_production
                                  .group_by { |p| p.contract.production }
                                  .map { |production, payments| build_summary(production, payments) }
                                  .sort_by { |s| [ -s[:overdue_count], -s[:outstanding] ] }
      end
    end

    # A single receivable: its status, the collect-in-person QR, the reminder
    # composer, and (when the contract allows it) a record-offline-payment panel.
    def show
      @payment    = find_payment
      @contract   = @payment.contract
      @contractor = @contract.contractor
      # Only mint/expose a pay link when there's actually a settled amount to charge.
      @pay_url = @payment.collectable_online? ? pay_contract_url(token: @payment.payment_token!) : nil
    end

    # Nudge the payer about this receivable. Renders the seeded
    # contract_payment_reminder template (channel "both") to the payer's Person —
    # in-app message if they have an account, plus an email carrying the pay link.
    def remind
      @payment    = find_payment
      contract    = @payment.contract
      contractor  = contract.contractor
      person      = contractor&.ensure_person!

      if person.nil? || person.email.blank?
        redirect_to manage_money_incoming_payment_path(@payment),
                    alert: "No email on file for this payer — add one on the contract to send a reminder."
        return
      end

      pay_url = @payment.collectable_online? ? pay_contract_url(token: @payment.payment_token!) : manage_contract_url(contract)

      ContentTemplateService.deliver(
        template_key: "contract_payment_reminder",
        variables: {
          payer_name: contractor.name.presence || person.name,
          organization_name: Current.organization.name,
          amount: number_to_currency(@payment.amount),
          description: @payment.description.presence || "a payment",
          due_date: @payment.due_date.strftime("%B %-d, %Y"),
          pay_url: pay_url,
          custom_message: params[:custom_message].to_s.strip
        },
        sender: Current.user,
        recipients: [ person ],
        organization: Current.organization,
        production: contract.production,
        mailer_class: Manage::ContractPaymentMailer,
        mailer_method: :payment_reminder
      )

      redirect_to manage_money_incoming_payment_path(@payment),
                  notice: "Reminder sent to #{person.email}."
    end

    private

    # Pending money owed TO this org, across every contract.
    def incoming_scope
      ContractPayment.direction_incoming.status_pending
                     .joins(:contract)
                     .where(contracts: { organization_id: Current.organization.id })
    end

    # Detail/remind look up by id within the org, not restricted to pending — a
    # just-collected payment is still viewable from its link.
    def find_payment
      ContractPayment.direction_incoming
                     .joins(:contract)
                     .where(contracts: { organization_id: Current.organization.id })
                     .find(params[:id])
    end

    def set_production
      return if params[:production_id].blank?

      @production = Current.organization.productions.find_by(id: params[:production_id])
    end

    def build_summary(production, payments)
      overdue = payments.select(&:overdue?)
      {
        production: production,
        outstanding: payments.sum { |p| p.amount.to_f },
        overdue_count: overdue.size,
        overdue_amount: overdue.sum { |p| p.amount.to_f },
        count: payments.size
      }
    end

    # Continuous month-by-month buckets from this month to the window end (or the
    # last upcoming payment when the window is "All", capped at 24 months so the
    # timeline stays readable). Empty months are included so the cadence reads well.
    # TBD-amount payments (revenue shares) are counted but not summed.
    def build_monthly_forecast(payments, window_end)
      start_month = Date.current.beginning_of_month
      last = window_end || payments.map(&:due_date).max
      return [] if last.nil?

      last = [ last, start_month >> 24 ].min
      last_month = last.beginning_of_month

      months = []
      m = start_month
      while m <= last_month
        next_m = m >> 1
        in_month = payments.select { |p| p.due_date >= m && p.due_date < next_m }
        settled = in_month.reject(&:amount_tbd?)
        months << {
          month: m,
          total: settled.sum { |p| p.amount.to_f },
          count: in_month.size,
          tbd_count: in_month.count(&:amount_tbd?)
        }
        m = next_m
      end
      months
    end
  end
end

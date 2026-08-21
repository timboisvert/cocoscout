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

    # Ways an incoming payment can arrive outside CocoScout's Stripe rail — the
    # one list shared with the contract page (ContractPayment::RECEIVED_PAYMENT_METHODS).
    RECEIVED_METHODS = ContractPayment::RECEIVED_PAYMENT_METHODS

    # Forward-looking windows for the "what's coming in" view.
    WINDOWS = [
      { key: "1m",  label: "30 days",   months: 1 },
      { key: "3m",  label: "3 months",  months: 3 },
      { key: "6m",  label: "6 months",  months: 6 },
      { key: "12m", label: "12 months", months: 12 },
      { key: "all", label: "All",       months: nil }
    ].freeze

    before_action :set_production, only: %i[index payments received]

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

      # A taste of what's already been collected — the page is a record, not
      # only a to-do list. A handful of the most recent, with the full book one
      # click away on the Received page.
      received = received_scope
      received = received.where(contracts: { production_id: @production.id }) if @production
      @received_count = received.count
      @received_payments = received.includes(contract: [ :contractor, :production ])
                                   .order(paid_date: :desc, updated_at: :desc)
                                   .limit(RECENT_RECEIVED_LIMIT).to_a

      unless @production
        # Org-wide list layout: one flat list by due date (default, overdue and
        # soonest-due first) or grouped by production.
        @group_by = params[:group] == "production" ? "production" : "due_date"

        with_production, @orphan_payments = @payments.partition { |p| p.contract.production_id.present? }
        @production_summaries = with_production
                                  .group_by { |p| p.contract.production }
                                  .map { |production, payments| build_summary(production, payments) }
                                  .sort_by { |s| [ -s[:overdue_count], -s[:outstanding] ] }
      end
    end

    # Lazily-loaded accordion body on the by-production incoming list: one
    # production's pending payments, honoring the same forward window as the
    # index (overdue always shows). Rows link straight to the payment detail.
    def payments
      return head :not_found unless @production

      window = WINDOWS.find { |w| w[:key] == params[:window] } || WINDOWS.find { |w| w[:key] == "3m" }
      window_end = window[:months] ? (Date.current >> window[:months]) : nil

      all_pending = incoming_scope.includes(contract: [ :contractor, :production ])
                                  .where(contracts: { production_id: @production.id })
                                  .by_due_date.to_a
      @payments = window_end ? all_pending.select { |p| p.overdue? || p.due_date <= window_end } : all_pending
      render layout: false
    end

    # Every payment that has already arrived — the full received book the
    # index's "Recently received" teaser links to. Production-scopable the
    # same way the index is.
    def received
      received = received_scope
      received = received.where(contracts: { production_id: @production.id }) if @production
      @received_total = received.where.not(amount: nil).sum(:amount)
      @received_payments = received.includes(contract: [ :contractor, :production ])
                                   .order(paid_date: :desc, updated_at: :desc)
                                   .to_a
    end

    # A single receivable: its status, the collect-in-person QR, the reminder
    # composer, and (when the contract allows it) a record-offline-payment panel.
    def show
      @payment    = find_payment
      @contract   = @payment.contract
      @contractor = @contract.contractor
      # Only mint/expose a pay link when there's actually a settled amount to charge.
      @pay_url = @payment.collectable_online? ? pay_contract_url(token: @payment.payment_token!) : nil
      @received_methods = RECEIVED_METHODS
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
          custom_message: params[:custom_message].to_s.strip,
          # Only the ways this contract says they may pay; blank means the
          # template shows CocoScout alone.
          other_payment_methods: contract.offline_payment_methods_sentence.to_s
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

    # Mark an incoming payment as received outside CocoScout (cash, check, Zelle,
    # Venmo, bank transfer…). Unlike the contract's offline-payment flow, this
    # isn't gated on the contract's allowed methods — the money already reached
    # the org, so we just record it as paid (as if it had settled via Stripe).
    def mark_received
      @payment = find_payment

      unless @payment.status_pending?
        redirect_to manage_money_incoming_payment_path(@payment),
                    alert: "This payment is already marked #{@payment.status}."
        return
      end

      paid_on =
        begin
          params[:paid_date].present? ? Date.parse(params[:paid_date]) : Date.current
        rescue ArgumentError
          Date.current
        end

      @payment.mark_paid!(
        paid_on: paid_on,
        method: params[:payment_method].presence,
        reference: params[:reference_number].presence,
        amount: params[:payment_amount].presence
      )

      redirect_to manage_money_incoming_payment_path(@payment),
                  notice: "Payment recorded as received."
    end

    private

    # How many recent collections the index teases before handing off to the
    # full Received page.
    RECENT_RECEIVED_LIMIT = 6

    # Money owed to this org that has actually arrived, however it came
    # (pay link, recorded check, netted out of a payout).
    def received_scope
      ContractPayment.direction_incoming.status_paid
                     .joins(:contract)
                     .where(contracts: { organization_id: Current.organization.id })
    end

    # Pending money owed TO this org that someone actually has to collect.
    #
    # Charges settled by deduction are excluded on purpose: they net out of the
    # counterparty's payout automatically, so nobody invoices them, chases them
    # or sends a reminder about them. Listing them here inflated "owed to us"
    # with money that will never arrive as a payment.
    def incoming_scope
      collectable_incoming
    end

    # Everything owed to us, including the amounts that settle by deduction —
    # for totals and reporting, where the money is real even though the
    # collection is automatic. Defined in MoneyTodoService so this page and the
    # Money hub count the same money.
    def all_incoming
      MoneyTodoService.all_incoming(Current.organization)
    end

    def collectable_incoming
      MoneyTodoService.collectable_incoming(Current.organization)
    end

    def deduction_settled_incoming
      MoneyTodoService.deduction_settled_incoming(Current.organization)
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

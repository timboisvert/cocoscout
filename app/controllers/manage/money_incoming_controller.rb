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

    before_action :set_production, only: :index

    # Org-wide list grouped by production (mirrors money_payouts#index), or a
    # single production's incoming payments when a production_id is present.
    def index
      if @production
        @payments = incoming_scope
                      .where(contracts: { production_id: @production.id })
                      .includes(contract: :contractor)
                      .by_due_date.to_a
      else
        all = incoming_scope
                .includes(contract: [ :contractor, :production ])
                .by_due_date.to_a

        with_production, @orphan_payments = all.partition { |p| p.contract.production_id.present? }
        @production_summaries = with_production
                                  .group_by { |p| p.contract.production }
                                  .map { |production, payments| build_summary(production, payments) }
                                  .sort_by { |s| [ -s[:overdue_count], -s[:outstanding] ] }
        @payments = all
      end

      assign_totals(@payments)
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

    def assign_totals(payments)
      overdue = payments.select(&:overdue?)
      @total_outstanding = payments.sum { |p| p.amount.to_f }
      @overdue_count     = overdue.size
      @total_overdue     = overdue.sum { |p| p.amount.to_f }
    end
  end
end

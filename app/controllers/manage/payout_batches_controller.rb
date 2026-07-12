# frozen_string_literal: true

module Manage
  # Org-facing "Run payout" flow: pay everyone with a connected bank and a
  # positive balance at once through Stripe Connect. Pro-tier (gated by
  # Manage::PaidFeatureGate as a Money feature).
  class PayoutBatchesController < Manage::ManageController
    before_action :ensure_org_owner_or_manager

    def index
      @batches = organization.payout_batches.recent.includes(:created_by).limit(50)
    end

    # Review who would be paid before running anything.
    def new
      load_preview
    end

    def create
      batch = PayoutBatchService.build_for(organization: organization, created_by: Current.user)

      if batch.items.empty?
        batch.destroy
        redirect_to manage_new_payout_batch_path, alert: "No one has a connected bank and a positive balance to pay right now." and return
      end

      method = params[:funding_method].presence_in(PayoutBatchService::FUNDING_METHODS) || "ach"
      PayoutBatchService.fund!(batch, method: method)

      redirect_to manage_payout_batch_path(batch),
                  notice: "Payout run started — #{helpers.number_to_currency(batch.total_cents / 100.0)} to #{batch.items.size} #{'person'.pluralize(batch.items.size)}."
    rescue PayoutBatchService::Error => e
      redirect_to manage_new_payout_batch_path,
                  alert: "Couldn't start the payout: #{e.message}. Make sure your organization has a payment method set up to fund payouts."
    end

    def show
      @batch = organization.payout_batches.find(params[:id])
    end

    # Set the org's automatic payout cadence (manual / weekly / monthly).
    def update_schedule
      schedule = params[:payout_schedule].to_s
      day = case schedule
      when "weekly"  then params[:weekly_day]
      when "monthly" then params[:monthly_day]
      end

      if organization.update(
        payout_schedule: schedule,
        payout_schedule_day: day.presence,
        payout_funding_method: params[:payout_funding_method].presence || organization.payout_funding_method
      )
        redirect_to manage_payout_batches_path, notice: "Payout schedule updated."
      else
        redirect_to manage_payout_batches_path,
                    alert: "Couldn't update schedule: #{organization.errors.full_messages.to_sentence}"
      end
    end

    private

    def organization
      Current.organization
    end

    # Split everyone the org owes into those ready to be paid (connected bank)
    # and those who still need to connect. Used by the review screen.
    def load_preview
      @ready = []
      @not_ready = []

      organization.payout_balances_by_payee.each do |(payee_type, payee_id), cents|
        next unless cents.positive? && %w[Person Contractor Group].include?(payee_type)

        payee = payee_type.constantize.find_by(id: payee_id)
        next unless payee

        row = { payee: payee, cents: cents }
        if payee.respond_to?(:can_receive_payouts?) && payee.can_receive_payouts?
          @ready << row
        else
          @not_ready << row
        end
      end

      @ready.sort_by! { |r| -r[:cents] }
      @not_ready.sort_by! { |r| -r[:cents] }
      @ready_total_cents = @ready.sum { |r| r[:cents] }
    end
  end
end

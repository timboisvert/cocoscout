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
      # Payees in an open run who can't be paid yet (no connected bank) — their
      # transfer would fail, so warn before funding.
      @not_ready_items = if @batch.open?
        @batch.items.includes(:payee).pending.reject do |item|
          item.payee.respond_to?(:can_receive_payouts?) && item.payee.can_receive_payouts?
        end
      else
        []
      end
    end

    # Fund and pay an existing open run (e.g. a performer run built via
    # "add to payout run"). ACH-debits the org, then transfers to each payee.
    def fund
      batch = organization.payout_batches.find(params[:id])
      unless batch.open? && batch.items.pending.any?
        redirect_to(manage_payout_batch_path(batch), alert: "There's nothing to pay in this run.") and return
      end

      PayoutBatchService.fund!(batch, method: "ach")
      redirect_to manage_payout_batch_path(batch),
                  notice: "Funding started — everyone in this run gets paid once it clears."
    rescue PayoutBatchService::Error => e
      redirect_to manage_payout_batch_path(batch), alert: e.message
    end

    # Discard an unfunded draft run: undo everything it staged. Staff hours it
    # pulled in go back to the approved-unpaid pool, and the earning ledger
    # entries it posted are reversed. Only a draft (never-funded) run can be
    # discarded — once funding starts, the money is moving.
    def destroy
      batch = organization.payout_batches.find(params[:id])
      unless batch.status == "draft"
        redirect_to(manage_payout_batch_path(batch),
                    alert: "Only a draft run that hasn't been funded can be discarded.") and return
      end

      PayoutBatchService.discard!(batch)
      redirect_to manage_payout_batches_path,
                  notice: "Draft run discarded. Any staff hours it held are back in what's waiting to be paid."
    end

    # Connect the bank/card the org funds payout runs from (Stripe Checkout).
    def connect_funding
      return_to = safe_funding_return_to(params[:return_to])
      success = manage_payout_funding_return_url + "?session_id={CHECKOUT_SESSION_ID}"
      success += "&return_to=#{CGI.escape(return_to)}" if return_to

      url = PayoutFundingService.new(organization).setup_session_url(
        success_url: success,
        cancel_url: return_to ? "#{request.base_url}#{return_to}" : manage_payout_batches_url
      )
      redirect_to url, allow_other_host: true
    rescue PayoutFundingService::Error => e
      redirect_to(return_to || manage_payout_batches_path, alert: "Couldn't start funding setup: #{e.message}")
    end

    def funding_return
      PayoutFundingService.new(organization).save_from_session!(params[:session_id])
      redirect_to(safe_funding_return_to(params[:return_to]) || manage_payout_batches_path,
                  notice: "Funding source connected — you're ready to run payouts.")
    rescue PayoutFundingService::Error => e
      redirect_to(safe_funding_return_to(params[:return_to]) || manage_payout_batches_path,
                  alert: "Couldn't save your funding source: #{e.message}")
    end

    def remove_funding
      PayoutFundingService.new(organization).remove!
      redirect_to(safe_funding_return_to(params[:return_to]) || manage_payout_batches_path,
                  notice: "Funding source removed.")
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

    # Only allow a same-app relative path as the post-funding redirect target,
    # so ?return_to= can't be used as an open redirect.
    def safe_funding_return_to(path)
      path if path.to_s.start_with?("/") && !path.to_s.start_with?("//")
    end

    def organization
      Current.organization
    end

    # Split everyone the org owes into those ready to be paid (connected bank)
    # and those who still need to connect. Used by the review screen.
    CATEGORY_LABELS = { "performer" => "Show payouts", "staffing" => "Staff pay" }.freeze

    # Preview EXACTLY what a New run would create: each payee's balance minus what
    # they already have queued in another open run (same rule build_for uses), so
    # the preview and the actual run agree. Each row carries a breakdown of what
    # the amount is for.
    def load_preview
      committed = PayoutBatchService.committed_by_payee(organization)

      earnings = organization.payout_ledger_entries.where(entry_type: "earning")
                             .group(:payee_type, :payee_id, :category).sum(:amount_cents)
      earnings_by_payee = Hash.new { |h, k| h[k] = [] }
      earnings.each { |(ptype, pid, cat), cents| earnings_by_payee[[ptype, pid]] << [cat, cents] }

      @ready = []
      @not_ready = []

      organization.payout_balances_by_payee.each do |(payee_type, payee_id), balance|
        next unless PayoutBatchService::PAYABLE_TYPES.include?(payee_type)

        committed_cents = committed[[payee_type, payee_id]].to_i
        available = balance - committed_cents
        next unless available.positive?

        payee = payee_type.constantize.find_by(id: payee_id)
        next unless payee

        row = {
          payee: payee,
          cents: available,
          committed_cents: committed_cents,
          lines: preview_breakdown(earnings_by_payee[[payee_type, payee_id]], balance, committed_cents)
        }
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

    # A "what for" breakdown that sums to `available` (balance - committed):
    # earnings grouped by category, any advance/payout adjustment, then a
    # deduction for whatever's already queued in another open run.
    def preview_breakdown(category_pairs, balance, committed_cents)
      lines = category_pairs.reject { |_cat, cents| cents.zero? }.map do |cat, cents|
        { label: CATEGORY_LABELS[cat] || cat.to_s.titleize, cents: cents }
      end
      gross = category_pairs.sum { |_cat, cents| cents }
      adjustment = balance - gross
      lines << { label: "Advances / adjustments", cents: adjustment } if adjustment != 0
      lines << { label: "Already queued in an open run", cents: -committed_cents } if committed_cents.positive?
      lines
    end
  end
end

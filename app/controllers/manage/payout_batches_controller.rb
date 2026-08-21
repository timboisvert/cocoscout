# frozen_string_literal: true

module Manage
  # Org-facing "Run payout" flow: pay everyone with a connected bank and a
  # positive balance at once through Stripe Connect. Pro-tier (gated by
  # Manage::PaidFeatureGate as a Money feature).
  class PayoutBatchesController < Manage::ManageController
    before_action :ensure_org_owner_or_manager

    def index
      # Catch up any collected contract money that missed its remittance (the
      # org's bank wasn't connected when it arrived). Idempotent and free when
      # there's nothing waiting.
      ContractPaymentCollection.remit_pending!(organization)

      # Active = anything short of fully done: drafts being built, runs funding/
      # paying, partially-paid runs waiting on people, and failed runs needing
      # attention. Completed (and the rare canceled) runs are history below.
      runs = organization.payout_batches.recent.includes(:created_by, items: :payee)
      @active_batches = runs.where.not(status: %w[completed canceled]).to_a
      @completed_batches = runs.where(status: %w[completed canceled]).limit(50).to_a

      # Each listed run's money by payee state — the columns that say WHY a run
      # is partially paid ("$250 waiting on Ned's bank"), not just that it is.
      @run_breakdowns = (@active_batches + @completed_batches).to_h { |b| [ b.id, b.money_by_item_state ] }

      # Where every dollar across ALL runs sits, by what has to happen to it:
      #   ready    — payable now: in a draft (fund the run) or a funded,
      #              partially-paid run (Pay remaining). Something YOU can do.
      #   funding  — ACH clearing on submitted runs; pays out by itself.
      #   waiting  — funded or drafted, but the payee has no bank yet. Nothing
      #              you can do but nudge them.
      #   paid     — all time.
      #   returned — paid and bounced back by the payee's bank (rare).
      # Ready/waiting come from the loaded active runs (there's no cap on those);
      # the rest are sums over every run the org has ever made.
      all_items = PayoutBatchItem.joins(:payout_batch).where(payout_batches: { organization_id: organization.id })
      funding_stage = %w[funding funded processing]
      settling = @active_batches.reject { |b| funding_stage.include?(b.status) }
      sum_state = ->(state, key) { settling.sum { |b| @run_breakdowns[b.id][state][key] } }
      @money_by_state = {
        ready: sum_state.call(:ready, :cents),
        funding: organization.payout_batches.where(status: funding_stage).sum(:total_cents),
        waiting: sum_state.call(:waiting, :cents),
        paid: all_items.where(status: "paid").sum(:amount_cents),
        returned: all_items.where(status: "returned").sum(:amount_cents)
      }
      @counts_by_state = {
        ready: sum_state.call(:ready, :count),
        funding: @active_batches.count { |b| funding_stage.include?(b.status) },
        waiting: sum_state.call(:waiting, :count),
        waiting_runs: settling.count { |b| @run_breakdowns[b.id][:waiting][:count].positive? },
        paid: organization.payout_batches.where(status: "completed").count,
        returned: all_items.where(status: "returned").count
      }
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
      @items = @batch.items.includes(:payee, payout_contributions: :source).order(:created_at).to_a

      # Every dollar on the run, by payee state (paid / ready / waiting on bank /
      # returned) — the boxes up top, and the list filter below.
      @breakdown = @batch.money_by_item_state(@items)
      @state_filter = params[:state].to_s.to_sym.presence_in(PayoutBatch::ITEM_STATES)
      @visible_items = @state_filter ? @items.select { |i| PayoutBatch.item_state(i) == @state_filter } : @items

      # Payees who can't be paid yet (no connected bank): in an open run they're
      # a pre-funding warning; in a funded, partially-paid run they're who the
      # run is still waiting on.
      @not_ready_items = if @batch.open? || @batch.status == "partially_paid"
        @items.select { |i| PayoutBatch.item_state(i) == :waiting }
      else
        []
      end
      # Unpaid items whose payee has since become payable (connected a bank, or
      # a failed transfer worth retrying) — what "Pay remaining" would send.
      @payable_remaining_items = if @batch.status == "partially_paid" && (@batch.funding_status == "succeeded" || @batch.skips_funding?)
        @items.select { |i| PayoutBatch.item_state(i) == :ready }
      else
        []
      end
    end

    # DEV ONLY: pretend Stripe's payment_intent.succeeded webhook arrived, so a
    # run stuck in "funding" can advance without the Stripe CLI forwarding
    # webhooks. A simulated webhook means no real money reached the test-mode
    # platform balance, so transfers would fail with "insufficient available
    # funds" — first top up the test balance with Stripe's bypass-pending test
    # token (its charges land straight in available balance). Also handles a
    # partially_paid run whose transfers already failed that way: top up and
    # retry. Production settles via the real webhook (stripe_webhooks#create).
    def simulate_funding
      raise ActionController::RoutingError, "Not Found" unless Rails.env.development?

      batch = organization.payout_batches.find(params[:id])
      case batch.status
      when "funding"
        dev_top_up_test_balance!(batch.total_cents)
        PayoutBatchService.advance_funding!(batch, "succeeded")
        redirect_to manage_payout_batch_path(batch), notice: "Simulated: test balance topped up, funding cleared, transfers attempted."
      when "partially_paid", "processing" # processing = crashed mid-process; retry is safe (paid items are skipped)
        remaining = batch.items.where.not(status: "paid").sum(:amount_cents)
        dev_top_up_test_balance!(remaining)
        PayoutBatchService.pay_remaining!(batch)
        redirect_to manage_payout_batch_path(batch), notice: "Simulated: test balance topped up, remaining transfers attempted."
      else
        redirect_to manage_payout_batch_path(batch), alert: "This run isn't waiting on funding."
      end
    rescue Stripe::StripeError, PayoutBatchService::Error => e
      redirect_to manage_payout_batch_path(batch), alert: "Simulation failed: #{e.message}"
    end

    # Send transfers to whoever in an already-funded, partially-paid run has
    # become payable since the last pass. No new funding — the original ACH
    # debit covered the whole run.
    def pay_remaining
      batch = organization.payout_batches.find(params[:id])
      PayoutBatchService.pay_remaining!(batch)
      redirect_to manage_payout_batch_path(batch),
                  notice: batch.reload.completed? ? "Everyone in this run is paid — run complete." : "Paid everyone who's ready. The rest stay on this run until they connect a bank."
    rescue PayoutBatchService::Error => e
      redirect_to manage_payout_batch_path(batch), alert: e.message
    end

    # Fund and pay an existing open run (e.g. a performer run built via
    # "add to payout run"). ACH-debits the org for whatever held money (course
    # sales, collected contract payments) doesn't cover, then transfers to each
    # payee — a fully-held run debits nothing and pays immediately.
    def fund
      batch = organization.payout_batches.find(params[:id])
      unless batch.open? && batch.items.pending.any?
        redirect_to(manage_payout_batch_path(batch), alert: "There's nothing to pay in this run.") and return
      end
      # A fund-free run pays from money already held — ACH-debiting the org to
      # pay itself would charge them twice. pay_now is that run's button.
      if batch.skips_funding?
        redirect_to(manage_payout_batch_path(batch), alert: "This run pays from money CocoScout already holds — use Pay now.") and return
      end

      PayoutBatchService.fund!(batch, method: "ach")
      redirect_to manage_payout_batch_path(batch),
                  notice: "Funding started — everyone in this run gets paid once it clears."
    rescue PayoutBatchService::Error => e
      redirect_to manage_payout_batch_path(batch), alert: e.message
    end

    # LEGACY: pay a pre-fold course-kind run (skips_funding?) — the money is
    # already in CocoScout's balance, so there's no ACH step. New runs carry
    # held money as held-funds lines on the performer run and go through #fund,
    # which debits nothing when held money covers the run.
    def pay_now
      batch = organization.payout_batches.find(params[:id])
      unless batch.skips_funding?
        redirect_to(manage_payout_batch_path(batch), alert: "This run needs funding first.") and return
      end
      unless batch.items.pending.any?
        redirect_to(manage_payout_batch_path(batch), alert: "There's nothing to pay in this run.") and return
      end
      if Stripe.api_key.blank?
        redirect_to(manage_payout_batch_path(batch), alert: "Payouts aren't configured yet.") and return
      end

      result = CoursePayoutRunExecutor.pay!(batch)
      if result.error.present?
        redirect_to manage_payout_batch_path(batch), alert: result.error
      else
        notice = "Paid #{result.paid} #{'payout'.pluralize(result.paid)} straight to their bank."
        notice += " #{result.failed} couldn't be sent — see below." if result.failed.positive?
        redirect_to manage_payout_batch_path(batch), notice: notice
      end
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

    # Dev-only: put test money in the platform's available balance so simulated
    # runs can actually transfer. tok_bypassPending is Stripe's documented test
    # token whose charges skip "pending" and land in available balance.
    def dev_top_up_test_balance!(cents)
      return unless Rails.env.development? && cents.positive?

      Stripe::Charge.create(
        amount: cents, currency: "usd", source: "tok_bypassPending",
        description: "Dev top-up for simulated payout run"
      )
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
      earnings.each { |(ptype, pid, cat), cents| earnings_by_payee[[ ptype, pid ]] << [ cat, cents ] }

      @ready = []
      @not_ready = []

      organization.payout_balances_by_payee.each do |(payee_type, payee_id), balance|
        next unless PayoutBatchService::PAYABLE_TYPES.include?(payee_type)

        committed_cents = committed[[ payee_type, payee_id ]].to_i
        available = balance - committed_cents
        next unless available.positive?

        payee = payee_type.constantize.find_by(id: payee_id)
        next unless payee

        row = {
          payee: payee,
          cents: available,
          committed_cents: committed_cents,
          lines: preview_breakdown(earnings_by_payee[[ payee_type, payee_id ]], balance, committed_cents)
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

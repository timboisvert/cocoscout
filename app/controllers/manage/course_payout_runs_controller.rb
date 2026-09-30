# frozen_string_literal: true

module Manage
  # The Courses-side window onto the org's ONE payout run, for orgs WITHOUT
  # Pro: Money (and its payout-run pages) is Pro-only, but courses are free, so
  # a free org sees and pays its course money here — only the course lines.
  # A Pro org never uses this page: it goes straight to the one run in Money,
  # so nobody has to check two places.
  #
  # Paying from here only works when everything pending is held money (course
  # sales, collected contract payments) — no bank debit. A run that also
  # carries bank-funded payouts (show pay, contractor payments) must be funded
  # from the Money page instead.
  class CoursePayoutRunsController < Manage::ManageController
    before_action :send_pro_orgs_to_the_one_run
    before_action :require_org_manager, only: :pay

    def show
      # Contract remittances ride this run too — catch up any that were
      # collected before the org could receive payouts.
      ContractPaymentCollection.remit_pending!(Current.organization)

      @run = current_run || recent_run
      # Course money only (and any other money held for the org): staff pay and
      # show payouts are Pro, and never shown on this free page.
      @items = @run ? @run.items.includes(:payee, :payout_contributions).order(:created_at).to_a.select { |i| held_item?(i) } : []
      @held_cents = @run&.open? ? @run.held_cents(@items) : 0
      pending_cents = @items.sum { |i| i.status == "pending" ? i.amount_cents : 0 }
      @bank_funded_cents = [ pending_cents - @held_cents, 0 ].max
    end

    def pay
      run = current_run
      if run.nil? || run.items.pending.none?
        redirect_to manage_course_payout_run_path, alert: "There's nothing to pay out right now."
        return
      end
      if Stripe.api_key.blank?
        redirect_to manage_course_payout_run_path, alert: "Payouts aren't configured yet."
        return
      end

      # Anything beyond held money needs the org's bank debited — that's the
      # Money page's fund & pay flow, not this button.
      pending_cents = run.items.pending.sum(:amount_cents)
      if pending_cents > run.held_cents
        redirect_to manage_course_payout_run_path,
          alert: "This run also includes payouts funded from your bank. Fund & pay it from Money → Payout Runs."
        return
      end

      PayoutBatchService.fund!(run)
      paid = run.reload.items.paid.count
      notice = "Paid #{paid} #{'payout'.pluralize(paid)} straight to their bank."
      unpaid = run.items.where.not(status: "paid").count
      notice += " #{unpaid} couldn't be sent yet — see below." if unpaid.positive?
      redirect_to manage_course_payout_run_path, notice: notice
    rescue PayoutBatchService::Error => e
      redirect_to manage_course_payout_run_path, alert: e.message
    end

    private

    # The one open run everything joins. Legacy course-kind drafts only show
    # through recent_run (they no longer accept new money).
    def current_run
      PayoutBatch.current_open_draft(Current.organization)
    end

    # Something to show when nothing is open: the most recent run that carried
    # course-style money.
    def recent_run
      PayoutBatch.of_kind(%w[payout performer course])
        .where(organization: Current.organization).recent.first
    end

    def held_item?(item)
      item.payout_contributions.any?(&:held_funds?)
    end

    # Pro orgs have the one payout run in Money; this page is only for orgs
    # without it.
    def send_pro_orgs_to_the_one_run
      return unless Current.organization&.feature_available?(:money)

      run = current_run
      redirect_to(run ? manage_payout_batch_path(run) : manage_payout_batches_path)
    end

    def require_org_manager
      return if Current.organization.manageable_by?(Current.user)

      redirect_to manage_course_payout_run_path,
        alert: "Only an organization owner or manager can send payouts."
    end
  end
end

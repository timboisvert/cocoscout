# frozen_string_literal: true

module Manage
  # The Courses-side window onto the org's ONE payout run (kind "performer" —
  # performers, contractors, course money, and contract remittances all ride
  # it; staff pay is the only separate run). Lives in Courses (a free module),
  # not the Pro-only Money section — the run pages under money/ are Pro-gated.
  #
  # Paying from here only works when everything pending is held money (course
  # sales, collected contract payments) — no bank debit. A run that also
  # carries bank-funded payouts (show pay, contractor payments) must be funded
  # from the Money page instead.
  class CoursePayoutRunsController < Manage::ManageController
    before_action :require_org_manager, only: :pay

    def show
      # Contract remittances ride this run too — catch up any that were
      # collected before the org could receive payouts.
      ContractPaymentCollection.remit_pending!(Current.organization)

      @run = current_run || recent_run
      @items = @run ? @run.items.includes(:payee, :payout_contributions).order(:created_at).to_a : []
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

    # The one open run everything joins. Falls back to legacy open course-kind
    # drafts only through recent_run (they no longer accept new money).
    def current_run
      PayoutBatch.of_kind("performer").open_runs
        .where(organization: Current.organization).order(:created_at).first
    end

    # Something to show when nothing is open: the most recent run that carried
    # course-style money — a performer run or a legacy course run.
    def recent_run
      PayoutBatch.of_kind(%w[performer course])
        .where(organization: Current.organization).recent.first
    end

    def require_org_manager
      return if Current.organization.manageable_by?(Current.user)

      redirect_to manage_course_payout_run_path,
        alert: "Only an organization owner or manager can send payouts."
    end
  end
end

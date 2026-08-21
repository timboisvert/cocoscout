# frozen_string_literal: true

module Manage
  # The course payout run: instructors + the org's own share, paid straight from
  # the course money CocoScout already holds. Lives in Courses (a free module),
  # not the Pro-only Money section — the existing run pages under money/ are
  # Pro-gated. No funding step: paying just transfers held funds out.
  class CoursePayoutRunsController < Manage::ManageController
    before_action :require_org_manager, only: :pay

    def show
      # Contract remittances ride this run too — catch up any that were
      # collected before the org could receive payouts.
      ContractPaymentCollection.remit_pending!(Current.organization)

      @run = current_course_run || recent_course_run
      @items = @run ? @run.items.includes(:payee, :payout_contributions).order(:created_at).to_a : []
    end

    def pay
      run = current_course_run
      if run.nil? || run.items.pending.none?
        redirect_to manage_course_payout_run_path, alert: "There's nothing to pay out right now."
        return
      end
      if Stripe.api_key.blank?
        redirect_to manage_course_payout_run_path, alert: "Payouts aren't configured yet."
        return
      end

      result = CoursePayoutRunExecutor.pay!(run)
      if result.error.present?
        redirect_to manage_course_payout_run_path, alert: result.error
        return
      end

      notice = "Paid #{result.paid} #{'payout'.pluralize(result.paid)} straight to their bank."
      notice += " #{result.failed} couldn't be sent — see below." if result.failed.positive?
      redirect_to manage_course_payout_run_path, notice: notice
    end

    private

    def current_course_run
      PayoutBatch.of_kind("course").open_runs
        .where(organization: Current.organization).order(:created_at).first
    end

    def recent_course_run
      PayoutBatch.of_kind("course").where(organization: Current.organization).recent.first
    end

    def require_org_manager
      return if Current.organization.manageable_by?(Current.user)

      redirect_to manage_course_payout_run_path,
        alert: "Only an organization owner or manager can send payouts."
    end
  end
end

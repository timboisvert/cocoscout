# frozen_string_literal: true

module Manage
  # The Money hub. Not a browse page: it answers "what needs me?" — financials
  # nobody has entered, payouts nobody has sent, money nobody has collected —
  # and hands off to the section pages for everything else. The full
  # per-production and per-course grids live on /money/financials/all.
  class MoneyController < Manage::ManageController
    # How many rows of each to-do section the hub shows before deferring to the
    # full page. Counts and totals always describe everything.
    HUB_ROWS = 5

    def index
      @selected_period = (params[:period].presence || "all_time").to_sym
      @productions = Current.user.accessible_productions.schedulable.order(:name)
      @org_summary = FinancialSummaryService.new(@productions).summary_for_period(@selected_period)

      # Nothing here is cached. A profit figure that's a few minutes stale is
      # still approximately right; a to-do row that's stale is actively wrong —
      # you enter a show's financials, come back, and it's still listed. One
      # phantom row costs trust in every other row on the page.
      @todo = MoneyTodoService.new(user: Current.user, organization: Current.organization, row_limit: HUB_ROWS)
    end

    # The hub no longer caches anything, so there's nothing to bust — but the
    # button (and the Financials pages that link it) still expect this endpoint.
    def refresh
      respond_to do |format|
        format.json { render json: { success: true } }
        format.html { redirect_to manage_money_index_path(period: params[:period]), notice: "Financials refreshed successfully" }
      end
    end
  end
end

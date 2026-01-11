# frozen_string_literal: true

module Manage
  class PayoutsController < Manage::ManageController
    before_action :set_production

    def index
      @payout_schemes = @production.payout_schemes.default_first
      @default_scheme = @payout_schemes.find(&:is_default)

      # Get shows with payout status
      @shows = @production.shows
                          .where(canceled: false)
                          .where("date_and_time <= ?", 1.day.from_now)
                          .order(date_and_time: :desc)
                          .includes(:show_financials, :show_payout)
                          .limit(20)

      # Summary stats
      @total_approved = @production.show_payouts.approved.sum(:total_payout) || 0
      @total_paid = @production.show_payouts.paid.sum(:total_payout) || 0
      @pending_count = @production.show_payouts.drafts.count
    end

    private

    def set_production
      @production = Current.production
    end
  end
end

# frozen_string_literal: true

module Manage
  # What Ticketing opens as on the free plan, when another organization
  # sells this one's dates under a connected contract (LinkedTicketSales):
  # each such production with how its dates are selling, read-only. Outside
  # the Pro module on purpose (PaidFeatureGate sends a free organization
  # here); nothing is set up, sold or refunded from it.
  class SoldElsewhereController < Manage::ManageController
    def index
      @productions = TicketingDashboard.new(Current.organization).sold_elsewhere_productions
      redirect_to manage_path if @productions.empty?
    end
  end
end

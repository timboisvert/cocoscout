# frozen_string_literal: true

module Manage
  # Ticketing's home: how sales are going, what needs the theater, and every
  # upcoming show a click away (TicketingDashboard).
  class TicketingController < Manage::TicketingBaseController
    def index
      @dashboard = TicketingDashboard.new(Current.organization, period: params[:period].presence || :last_30_days)
      @balance = CocoScoutBalance.summary(Current.organization)
      # The dates list: upcoming (a production with its next dates), or past (each date, newest first).
      @dates = params[:dates] == "past" ? "past" : "upcoming"
    end
  end
end

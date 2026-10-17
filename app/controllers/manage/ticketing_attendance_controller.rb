# frozen_string_literal: true

module Manage
  # Ticketing → Attendance: everyone holding a ticket, date by date, for a
  # week or any range (Ticketing::Attendance). Counts only; the money is on
  # each date's page and in Reports.
  class TicketingAttendanceController < Manage::TicketingBaseController
    PERIODS = { "this_week" => "This week", "last_week" => "Last week", "last_7_days" => "Last 7 days", "this_month" => "This month" }.freeze
    RANGE = /\A(\d{4}-\d{2}-\d{2})\.\.(\d{4}-\d{2}-\d{2})\z/

    def index
      # The custom-range form sends from and to; the page's one period param
      # carries them as "from..to" so the other filters keep the range.
      if params[:from].present? && params[:to].present?
        return redirect_to manage_ticketing_attendance_path(filter: "#{params[:from]}..#{params[:to]}", production: params[:production].presence)
      end

      @filter, @from, @to = chosen_range
      @production_id = Current.organization.productions.where(id: params[:production]).pick(:id)
      @attendance = Ticketing::Attendance.new(Current.organization, from: @from, to: @to, production_id: @production_id)
      @productions = Current.organization.productions.joins(:ticket_listings).distinct.order(:name)
    end

    private

    def chosen_range
      key = params[:filter].to_s
      today = Date.current
      case key
      when "last_week" then [ key, (today - 7).beginning_of_week, (today - 7).end_of_week ]
      when "last_7_days" then [ key, today - 6, today ]
      when "this_month" then [ key, today.beginning_of_month, today.end_of_month ]
      when RANGE
        from, to = [ Date.parse($1), Date.parse($2) ].sort
        to = from + 366 if to > from + 366
        [ "#{from}..#{to}", from, to ]
      else [ "this_week", today.beginning_of_week, today.end_of_week ]
      end
    rescue Date::Error
      [ "this_week", today.beginning_of_week, today.end_of_week ]
    end
  end
end

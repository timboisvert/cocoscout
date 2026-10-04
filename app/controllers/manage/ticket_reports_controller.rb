# frozen_string_literal: true

module Manage
  # Ticket sales for a month or a quarter (TicketSalesReport): the totals,
  # by show, by ticket type, by channel and by day, on screen or as CSVs.
  class TicketReportsController < Manage::TicketingBaseController
    include TicketingPeriods

    def show
      chosen_period
      @report = TicketSalesReport.new(Current.organization, from: @period[:from], to: @period[:to], basis: params[:basis])

      respond_to do |format|
        format.html
        format.csv do
          send_data @report.to_csv, type: "text/csv", filename: "ticket-sales-#{@period[:key]}-by-#{@report.basis}-date.csv"
        end
      end
    end

    # Everyone who bought in the period, as a spreadsheet.
    def buyers
      chosen_period
      report = TicketSalesReport.new(Current.organization, from: @period[:from], to: @period[:to], basis: params[:basis])
      send_data report.buyers_csv, type: "text/csv", filename: "ticket-buyers-#{@period[:key]}.csv"
    end
  end
end

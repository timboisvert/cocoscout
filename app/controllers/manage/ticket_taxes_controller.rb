# frozen_string_literal: true

module Manage
  # Taxes collected on tickets (TicketTaxReport), a month or a quarter at a
  # time, on screen or as a CSV for the accountant.
  class TicketTaxesController < Manage::TicketingBaseController
    def show
      @periods = period_choices
      @period = @periods.find { |p| p[:key] == params[:period] } || @periods.first
      @report = TicketTaxReport.new(Current.organization, from: @period[:from], to: @period[:to], basis: params[:basis])

      respond_to do |format|
        format.html
        format.csv do
          send_data @report.to_csv, type: "text/csv",
                                    filename: "taxes-collected-#{@period[:key]}-by-#{@report.basis}-date.csv"
        end
      end
    end

    private

    # The last 12 months and the last 4 quarters, newest first.
    def period_choices
      today = Date.current
      months = (0..11).map do |i|
        start = today.beginning_of_month << i
        { key: start.strftime("%Y-%m"), label: start.strftime("%B %Y"), from: start, to: start.end_of_month }
      end
      quarters = (0..3).map do |i|
        start = (today.beginning_of_quarter << (3 * i))
        { key: "#{start.year}-Q#{((start.month - 1) / 3) + 1}", label: "Q#{((start.month - 1) / 3) + 1} #{start.year}",
          from: start, to: start.end_of_quarter }
      end
      months + quarters
    end
  end
end

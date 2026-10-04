# frozen_string_literal: true

module Manage
  # Taxes collected on tickets (TicketTaxReport), a month or a quarter at a
  # time, on screen or as a CSV for the accountant.
  class TicketTaxesController < Manage::TicketingBaseController
    include TicketingPeriods

    def show
      chosen_period
      @report = TicketTaxReport.new(Current.organization, from: @period[:from], to: @period[:to], basis: params[:basis])

      respond_to do |format|
        format.html
        format.csv do
          send_data @report.to_csv, type: "text/csv",
                                    filename: "taxes-collected-#{@period[:key]}-by-#{@report.basis}-date.csv"
        end
      end
    end
  end
end

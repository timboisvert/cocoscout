# frozen_string_literal: true

module Manage
  # Money → Books → Taxes (plan F): one year, summarized the way the forms
  # ask. Books access, by the grid. Nothing is filed from here.
  class BooksTaxesController < Manage::ManageController
    def show
      @year = params[:year].to_i.clamp(2020, Date.current.year + 1)
      @year = Tax::Calendar.working_tax_year if params[:year].blank?
      @years = ((Current.organization.created_at.year)..Date.current.year).to_a.reverse
      @summary = BooksTaxSummary.new(Current.organization, year: @year, basis: params[:basis])
      respond_to do |format|
        format.html
        format.csv { send_data @summary.to_csv, filename: "taxes-#{@year}.csv", type: "text/csv" }
      end
    end
  end
end

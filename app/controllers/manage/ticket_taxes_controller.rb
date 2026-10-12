# frozen_string_literal: true

module Manage
  # The Sales tax page: tax collected on tickets, products and courses
  # (TicketTaxReport), a month or a quarter at a time, on screen or as a CSV
  # for the accountant; what's set aside for it (SalesTaxSetAside); marking
  # a period paid (SalesTaxRemittance); and how filing works.
  class TicketTaxesController < Manage::TicketingBaseController
    include TicketingPeriods

    def show
      chosen_period
      @report = TicketTaxReport.new(Current.organization, from: @period[:from], to: @period[:to], basis: params[:basis], kind: params[:kind])

      respond_to do |format|
        format.html do
          @remittances = Current.organization.sales_tax_remittances.order(:period_start).to_a
          @set_aside_cents = SalesTaxSetAside.cents(Current.organization)
          @set_aside_months = SalesTaxSetAside.by_month(Current.organization)
          @chicago = Current.organization.locations.where("city ILIKE ?", "chicago").exists?
          @ticket_tax = TicketTaxSetting.current(Current.organization)
        end
        format.csv do
          send_data @report.to_csv, type: "text/csv",
                                    filename: "taxes-collected-#{@report.kind}-#{@period[:key]}-by-#{@report.basis}-date.csv"
        end
      end
    end

    # "Mark paid": one tax, one period, paid to the government. Its tax stops
    # being set aside.
    def mark_paid
      attrs = params.require(:remittance).permit(:tax_name, :rate_bps, :basis, :period_start, :period_end, :amount, :paid_on, :reference)
      remittance = Current.organization.sales_tax_remittances.create!(
        tax_name: attrs[:tax_name], rate_bps: attrs[:rate_bps].to_i, basis: attrs[:basis],
        period_start: attrs[:period_start], period_end: attrs[:period_end],
        amount_cents: (BigDecimal(attrs[:amount].to_s.delete("$,").presence || "0") * 100).round.to_i,
        paid_on: attrs[:paid_on].presence || Date.current, reference: attrs[:reference].presence, recorded_by: Current.user
      )
      redirect_to back_to_report, notice: "#{remittance.tax_name} for #{period_words(remittance)} marked paid. " \
                                          "Its tax is no longer set aside."
    rescue ActiveRecord::RecordInvalid, ArgumentError => e
      redirect_to back_to_report, alert: e.message
    end

    # Undo a "Mark paid" made by mistake: the tax is set aside again.
    def unmark_paid
      remittance = Current.organization.sales_tax_remittances.find(params[:id])
      remittance.destroy!
      redirect_to back_to_report, notice: "#{remittance.tax_name} for #{period_words(remittance)} is no longer marked paid."
    end

    private

    def back_to_report
      manage_ticket_taxes_path(params.permit(:period, :basis, :kind).to_h.compact_blank)
    end

    def period_words(remittance)
      helpers.sales_tax_period_label(remittance.period_start, remittance.period_end)
    end
  end
end

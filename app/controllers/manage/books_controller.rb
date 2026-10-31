# frozen_string_literal: true

module Manage
  # The organization's books (Money → Books): the Overview (all your money,
  # money in and out for a period), then the record behind it: accounts,
  # entries, ticket money by show, and whether the nightly check agrees.
  # Open to the organization's managers and to anyone whose access grid
  # gives them Books (OrganizationAccess); Pro, by the feature gate.
  class BooksController < Manage::ManageController
    TABS = %w[overview accounts entries shows checks].freeze

    def show
      @tab = params[:tab].presence_in(TABS) || "overview"
      @report = BooksReport.new(Current.organization, basis: params[:basis])
      @period = params[:period].presence_in(BooksReport::PERIODS.keys) || "this_month"
      case @tab
      when "overview"
        @production_id = Current.organization.productions.find_by(id: params[:production])&.id
        @productions = Current.organization.productions.active.order(:name)
        @overview = @report.overview(range: BooksReport.period_range(@period), production_id: @production_id)
        @balance = CocoScoutBalance.summary(Current.organization)
        # find_by, not ChartOfAccounts.account: looking never creates the chart.
        @owed_to_payees_cents = Current.organization.ledger_accounts.find_by(key: "owed_to_payees")&.natural_balance_cents.to_i
        @bank_cents = Current.organization.ledger_accounts.find_by(key: "bank")&.natural_balance_cents.to_i
        # Nothing to check, and no chart to create, before the first posting.
        @mismatches = Current.organization.ledger_accounts.exists? ? BooksReconciliation.check(Current.organization) : []
      when "entries"
        @accounts = Current.organization.ledger_accounts.order(:code)
        @account = @accounts.find { |a| a.id == params[:account_id].to_i } if params[:account_id].present?
        @pagy, @entries = pagy(@report.entries(account_id: @account&.id, kind: params[:kind].presence_in(BooksReport::KIND_LABELS.keys)), limit: 50)
        # A recorded entry links to its page and wears a receipt mark.
        @records = Current.organization.money_records.with_attached_receipt
                          .where(id: @entries.select { |e| e.source_type == "MoneyRecord" }.map(&:source_id)).index_by(&:id)
      when "shows"
        @show_rows = @report.by_show
      when "checks"
        @mismatches = BooksReconciliation.check(Current.organization)
        @disagreements = BooksReconciliation.financials_vs_books(Current.organization, period_key: @period)
      end
    end

    # "Download this period": the Overview's money in and out as a CSV, one
    # row per line, with the show, production and category it belongs to.
    def download
      report = BooksReport.new(Current.organization, basis: params[:basis])
      period = params[:period].presence_in(BooksReport::PERIODS.keys) || "this_month"
      production_id = Current.organization.productions.find_by(id: params[:production])&.id
      csv = report.to_csv(range: BooksReport.period_range(period), production_id: production_id)
      send_data csv, type: "text/csv", filename: "books-#{period.tr('_', '-')}-#{report.basis == :cash ? 'when-moved' : 'when-earned'}.csv"
    end
  end
end

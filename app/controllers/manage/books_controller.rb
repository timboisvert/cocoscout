# frozen_string_literal: true

module Manage
  # The organization's books (Money → Books): the landing page (all your
  # money, money in and out for a period, and the sections), then the record
  # behind it, a page per section: accounts, entries, ticket money by show,
  # and whether the nightly check agrees. Statements, Taxes and Bank have
  # controllers of their own.
  # Open to the organization's managers and to anyone whose access grid
  # gives them Books (OrganizationAccess); Pro, by the feature gate.
  class BooksController < Manage::ManageController
    SECTIONS = %w[overview accounts entries shows checks].freeze

    def show
      # ?tab= was the old address of a section; it still answers.
      @tab = params[:section].presence_in(SECTIONS) || params[:tab].presence_in(SECTIONS) || "overview"
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
        @owed_to_contractors_cents = Current.organization.ledger_accounts.find_by(key: "owed_to_contractors")&.natural_balance_cents.to_i
        @bank_cents = Current.organization.ledger_accounts.find_by(key: "bank")&.natural_balance_cents.to_i
        # The books can't know what's in the bank until a statement says so.
        @bank_known = Current.organization.bank_statement_imports.exists?
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
        @disagreements = BooksReconciliation.financials_vs_books(Current.organization, period_key: @period)
      end
      # Nothing to check, and no chart to create, before the first posting.
      # Every page says how the checks stand (the Checks card's badge).
      @mismatches = Current.organization.ledger_accounts.exists? ? BooksReconciliation.check(Current.organization) : []
      load_record_choices unless @tab == "overview"
    end

    # The period's money in and out as a CSV, one row per line, with the show,
    # production and category it belongs to: "Every line" on Statements.
    def download
      report = BooksReport.new(Current.organization, basis: params[:basis])
      period = params[:period].presence_in(BooksReport::PERIODS.keys) || "this_month"
      production_id = Current.organization.productions.find_by(id: params[:production])&.id
      csv = report.to_csv(range: BooksReport.period_range(period), production_id: production_id)
      send_data csv, type: "text/csv", filename: "books-#{period.tr('_', '-')}-#{report.basis == :cash ? 'when-moved' : 'when-earned'}.csv"
    end

    private

    # The Record money modal's production and show menus.
    def load_record_choices
      return unless OrganizationAccess.allows?(Current.user, Current.organization, :books, :manage)

      @record_productions = Current.organization.productions.active.order(:name)
      @record_shows = Show.where(production_id: @record_productions.map(&:id), canceled: false)
                          .order(date_and_time: :desc).limit(400).select(:id, :production_id, :date_and_time, :secondary_name)
    end
  end
end

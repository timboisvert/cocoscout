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
    include BooksCategoriesGate
    SECTIONS = %w[overview accounts entries shows checks].freeze
    SHOWS_PER_PAGE = 50

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
        @pagy, shows = pagy(@report.shows_with_ticket_money, limit: SHOWS_PER_PAGE)
        @show_rows = @report.by_show(shows)
      when "checks"
        @disagreements = BooksReconciliation.financials_vs_books(Current.organization, period_key: @period)
      end
      # Nothing to check, and no chart to create, before the first posting.
      # The landing page says how the checks stand (the Checks card's badge)
      # from the last time they ran; the Checks page itself runs them now.
      # The other sections don't show them.
      @mismatches = if !Current.organization.ledger_accounts.exists? then []
      elsif @tab == "checks" then BooksReconciliation.record!(Current.organization)
      elsif @tab == "overview" then BooksReconciliation.last(Current.organization)
      else []
      end
      load_record_choices unless @tab == "overview"
    end

    # The period's money in and out as a spreadsheet, one row per line, with
    # the show, production and category it belongs to: "Every line" on
    # Statements. Asked for here and put together in the background
    # (BooksDownload); a GET, so someone who can only look can ask.
    def download
      BooksDownload.ask!(organization: Current.organization, by: Current.user, kind: "period",
                         options: { period: params[:period].presence_in(BooksReport::PERIODS.keys) || "this_month",
                                    basis: (params[:basis] == "cash" ? "cash" : nil),
                                    production: Current.organization.productions.find_by(id: params[:production])&.id })
      redirect_to manage_money_statements_path(anchor: "downloads"), notice: "Every line: #{BooksDownload::ASKED}"
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

# frozen_string_literal: true

module Manage
  # Money → Books → Statements (plan E1 and E2): profit and loss, the
  # balance sheet and cash flow, each on the page, printable, as a PDF
  # and as a CSV; the whole ledger as a CSV; and the lock that closes the
  # books through a date. Books access, by the grid; locking needs manage,
  # unlocking the owner.
  class BooksStatementsController < Manage::ManageController
    KINDS = %w[pnl balance cash].freeze

    before_action :require_change!, only: %i[lock unlock]

    def show
      @kind = params[:kind].presence_in(KINDS) || "pnl"
      @period = params[:period].presence_in(BooksReport::PERIODS.keys - [ "all_time" ]) || "this_month"
      @range = BooksReport.period_range(@period)
      @as_of = (Date.parse(params[:as_of]) rescue nil) || Date.current
      @by_production = params[:by_production] == "1"
      @statements = BooksStatements.new(Current.organization, basis: params[:basis])
      @statement = case @kind
      when "balance" then @statements.balance_sheet(@as_of)
      when "cash" then @statements.cash_flow(@range)
      else @statements.profit_and_loss(@range, by_production: @by_production)
      end
      @words = @statements.words

      respond_to do |format|
        format.html { render layout: "print" if params[:print] == "1" }
        format.pdf { send_data BooksStatementPdf.new(Current.organization, @statement).render, filename: "#{@statement.title.parameterize}-#{@statement.subtitle.parameterize}.pdf", type: "application/pdf", disposition: "inline" }
        format.csv { send_data @statements.to_csv(@statement), filename: "#{@statement.title.parameterize}-#{@statement.subtitle.parameterize}.csv", type: "text/csv" }
      end
    end

    def ledger
      send_data BooksStatements.new(Current.organization).ledger_csv, filename: "#{Current.organization.name.parameterize}-ledger-#{Date.current.iso8601}.csv", type: "text/csv"
    end

    # Lock the books through the last day of a month.
    def lock
      through = (Date.parse(params[:through]) rescue nil)&.end_of_month
      return redirect_to manage_money_statements_path, alert: "Pick the month to lock through." unless through
      return redirect_to manage_money_statements_path, alert: "That month is not over yet." if through >= Date.current

      Current.organization.update!(books_locked_through: through, books_locked_at: Time.current, books_locked_by: Current.user)
      redirect_to manage_money_statements_path, notice: "Locked. Nothing can be dated #{through.strftime('%B %-d, %Y')} or earlier; a change the engine has to make lands on #{(through + 1).strftime('%b %-d')} instead."
    end

    def unlock
      return redirect_to manage_money_statements_path, alert: "Only the owner can unlock the books." unless Current.organization.owned_by?(Current.user) || Current.user.superadmin?

      Current.organization.update!(books_locked_through: nil, books_locked_at: nil, books_locked_by: nil)
      redirect_to manage_money_statements_path, notice: "Unlocked. Lock them again when you are done."
    end

    private

    def require_change!
      return if OrganizationAccess.allows?(Current.user, Current.organization, :books, :manage)

      redirect_to manage_money_statements_path, alert: "You can look at the statements but not lock the books."
    end
  end
end

# frozen_string_literal: true

module Manage
  # The organization's books, read-only (BooksReport): balances, the entries
  # behind them, ticket money by show, and whether the nightly check agrees.
  # Superadmins only while ticketing — the first thing that posts here — is
  # being tested.
  class BooksController < Manage::ManageController
    TABS = %w[accounts entries shows checks].freeze

    before_action :ensure_user_is_superadmin
    before_action :ensure_org_owner_or_manager

    def show
      @tab = params[:tab].presence_in(TABS) || "accounts"
      @report = BooksReport.new(Current.organization, basis: params[:basis])
      case @tab
      when "entries"
        @accounts = Current.organization.ledger_accounts.order(:code)
        @account = @accounts.find { |a| a.id == params[:account_id].to_i } if params[:account_id].present?
        @pagy, @entries = pagy(@report.entries(account_id: @account&.id, kind: params[:kind].presence_in(BooksReport::KIND_LABELS.keys)), limit: 50)
      when "shows"
        @show_rows = @report.by_show
      when "checks"
        @mismatches = BooksReconciliation.check(Current.organization)
      end
    end
  end
end

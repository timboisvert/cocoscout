# frozen_string_literal: true

module Manage
  # Books' sections (Tim, 2026-11-02): cards on the Books landing page, the
  # way Money has its sections, and a breadcrumb back from each section's
  # own page. Never a tab strip.
  module BooksHelper
    # The cards, in order. mismatches: the nightly checks' findings, for the
    # badge on Checks.
    def books_section_cards(mismatches: [])
      [
        { icon: "queue-list", text: "Accounts", description: "Every account's balance", path: manage_money_books_section_path(section: "accounts") },
        { icon: "document-text", text: "Entries", description: "Every entry, with its lines", path: manage_money_books_section_path(section: "entries") },
        { icon: "ticket", text: "By show", description: "Ticket money, show by show", path: manage_money_books_section_path(section: "shows") },
        { icon: "check", text: "Checks", description: "The books against the records behind them", path: manage_money_books_section_path(section: "checks"), badge: Array(mismatches).size },
        { icon: "chart-bar", text: "Statements", description: "Profit and loss, balance sheet, cash flow", path: manage_money_statements_path },
        { icon: "banknotes", text: "Taxes", description: "A year, the way the forms ask", path: manage_money_taxes_path },
        { icon: "dollar-sign", text: "Bank", description: "Check the books against your bank statement", path: manage_money_bank_path }
      ]
    end

    # The breadcrumbs from Money down to a Books section's page.
    def books_breadcrumbs
      [ [ "Money", manage_money_index_path ], [ "Books", manage_money_books_path ] ]
    end

    # The Record money button: opens the modal on the page you're on.
    def record_money_link
      { text: "Record money", type: :button, data: { controller: "modal", action: "click->modal#open", modal_id: "record-money-modal" } }
    end
  end
end

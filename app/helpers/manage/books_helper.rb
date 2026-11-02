# frozen_string_literal: true

module Manage
  # Books' sections (Tim, 2026-11-02): one strip on every Books page, through
  # shared/settings_layout, so Statements, Taxes and Bank sit beside Overview
  # instead of in a filter bar.
  module BooksHelper
    BOOKS_SECTIONS = [
      [ "overview", "Overview" ], [ "accounts", "Accounts" ], [ "entries", "Entries" ], [ "shows", "By show" ],
      [ "checks", "Checks" ], [ "statements", "Statements" ], [ "taxes", "Taxes" ], [ "bank", "Bank" ]
    ].freeze

    # keep: the period and basis to carry between the Books report sections.
    def books_sections(keep = {})
      keep = keep.compact_blank
      BOOKS_SECTIONS.map do |key, label|
        path = case key
        when "statements" then manage_money_statements_path
        when "taxes" then manage_money_taxes_path
        when "bank" then manage_money_bank_path
        when "overview" then manage_money_books_path(keep)
        else manage_money_books_path(keep.merge(tab: key))
        end
        { key: key, label: label, path: path }
      end
    end

    # The Record money button: opens the modal on the page you're on.
    def record_money_link
      { text: "Record money", type: :button, data: { controller: "modal", action: "click->modal#open", modal_id: "record-money-modal" } }
    end
  end
end

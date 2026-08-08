# frozen_string_literal: true

module Manage
  module MoneyPayoutsHelper
    # The status columns the Awaiting Payout grid can show, in display order.
    # Each maps to a slice of the money by what still has to happen to it:
    #   to_pay    — nobody has done anything; needs staging in a run (or paying)
    #   in_draft  — staged in a payout run that hasn't been submitted yet
    #   in_flight — in a submitted run (funding/clearing); nothing left to do
    #   paid      — already paid out
    AWAITING_PAYOUT_COLUMNS = {
      to_pay: { label: "To pay", color: "text-pink-600" },
      in_draft: { label: "In draft run", color: "text-amber-600" },
      in_flight: { label: "In flight", color: "text-blue-600" },
      paid: { label: "Paid", color: "text-green-600" }
    }.freeze

    # Splits show-payout line items into the four column buckets above.
    # Returns { amounts: {col => Float}, counts: {col => Integer} } — amounts are
    # the payees' nets, counts are people.
    #
    # The bucketing itself lives in MoneyTodoService, which both the Payouts page
    # and the Money hub build their rows from — two copies would let the hub's
    # totals drift from the page's.
    def awaiting_payout_breakdown(line_items)
      MoneyTodoService.payout_breakdown(line_items)
    end

    # One right-aligned money cell for the grid. Zero renders as a quiet dash so
    # the eye lands only on columns that actually hold money.
    def awaiting_payout_cell(amount, column, bold: false)
      if amount.to_f > 0.004
        weight = bold ? "font-bold" : "font-medium"
        { value: number_to_currency(amount), class: "#{AWAITING_PAYOUT_COLUMNS.fetch(column)[:color]} #{weight}" }
      else
        { value: "—", class: "text-gray-400" }
      end
    end
  end
end

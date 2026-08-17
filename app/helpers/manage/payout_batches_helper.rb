# frozen_string_literal: true

module Manage
  module PayoutBatchesHelper
    # The money-state columns a list of payout runs can show, in display order.
    # Same idea as the Awaiting Payout grid's columns: each is a slice of a
    # run's money by what still has to happen to it (see PayoutBatch::ITEM_STATES).
    # Colors echo the lifecycle badges — waiting-on-bank is the blue "waiting on
    # payees" state, ready is the pink "you can act" state.
    RUN_STATE_COLUMNS = {
      ready: { label: "Ready to pay", color: "text-pink-600" },
      waiting: { label: "Waiting on bank", color: "text-blue-600" },
      paid: { label: "Paid", color: "text-green-600" },
      returned: { label: "Returned", color: "text-red-600" }
    }.freeze

    # Which columns to render for a set of run breakdowns (from
    # PayoutBatch#money_by_item_state): only the states that hold money in at
    # least one row, so a page of settled runs doesn't sprout empty "Waiting"
    # columns. Always at least Paid.
    def run_state_columns(breakdowns)
      cols = RUN_STATE_COLUMNS.keys.select { |state| breakdowns.any? { |b| b[state][:cents].positive? } }
      cols.empty? ? [ :paid ] : cols
    end

    # One right-aligned cell for a run row: the amount in that state's color,
    # or a quiet dash. `count` (payees) becomes a small subvalue when given.
    def run_state_cell(bucket, column, bold: false)
      cents = bucket[:cents]
      return { value: "—", class: "text-gray-300" } unless cents.positive?

      meta = RUN_STATE_COLUMNS.fetch(column)
      cell = { value: number_to_currency(cents / 100.0), class: "#{meta[:color]} #{bold ? 'font-semibold' : 'font-medium'}" }
      if bucket[:count].to_i.positive?
        cell[:subvalue] = pluralize(bucket[:count], "payee")
      end
      cell
    end

    # Trace a payout contribution back to the record that created it, so a manager
    # can click a line inside a run and land on the show / advance / contract /
    # course it came from — and keep tracing from there. Returns nil when the
    # source can't be linked (the caller renders plain text in that case).
    def payout_contribution_source_path(contribution)
      source = contribution.source
      return nil if source.nil?

      case source
      when ShowPayoutLineItem
        show = source.show_payout&.show
        show && manage_money_show_payout_path(show)
      when PersonAdvance
        source.production && manage_money_advance_path(source.production, source)
      when ContractPayment
        source.contract && manage_contract_path(source.contract)
      when CourseOfferingPayout
        manage_course_offering_payout_path(source.course_offering)
      when CourseOfferingPayoutLineItem
        source.course_offering && manage_course_offering_payout_path(source.course_offering)
      end
    end
  end
end

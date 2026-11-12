# frozen_string_literal: true

# The Turbo Stream answer to an action on a bank line (Tim, 2026-11-02: no
# bouncing between pages): the row changes in place, the tiles and counts
# follow, and the Record this line modal resets once a record is saved.
# Shared by the bank page's own actions and Record money's save.
module BankStatementStreams
  extend ActiveSupport::Concern

  private

  def bank_line_streams(line, reset_modal: false)
    org = Current.organization
    summary = BankStatementSummary.new(org)
    render partial: "manage/bank_statements/line_changed", formats: [ :turbo_stream ], locals: {
      line: line, summary: summary, filters: bank_filters,
      looks_like: BankStatementSummary.candidates_for(org, [ line ])[line.id],
      hint: (line.description_key && BankStatementSummary.hints_for(org, [ line ])[line.description_key]),
      reset_modal: reset_modal, **(reset_modal ? bank_record_modal_locals : {})
    }
  end

  def bank_filters
    params.permit(:month, :kind, :page).to_h.compact_blank
  end

  # The Record this line modal's forms: a blank record of each kind and the
  # choices for the production menus.
  def bank_record_modal_locals(records: {})
    org = Current.organization
    productions = org.productions.active.order(:name)
    shows = Show.where(production_id: productions.map(&:id), canceled: false).order(date_and_time: :desc).limit(400).select(:id, :production_id, :date_and_time, :secondary_name)
    { records: { "in" => MoneyRecord.blank_for(org, "in"), "out" => MoneyRecord.blank_for(org, "out") }.merge(records), productions: productions, shows: shows }
  end
end

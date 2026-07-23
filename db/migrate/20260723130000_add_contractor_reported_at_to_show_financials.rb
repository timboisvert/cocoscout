# frozen_string_literal: true

# Phase 6: when a contractor sells their own tickets (Case 2), they self-report
# the sales from /my/contracts. This records that a given show's financials came
# from the contractor rather than a manager — we trust the number, but keep the
# provenance.
class AddContractorReportedAtToShowFinancials < ActiveRecord::Migration[8.1]
  def change
    add_column :show_financials, :contractor_reported_at, :datetime
  end
end

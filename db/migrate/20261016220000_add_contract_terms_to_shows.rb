# frozen_string_literal: true

# One contracted date's own terms, when they differ from the deal (Review the
# dates, 2026-10-16): { "amount" => 0.0 } for a rehearsal's rate, a per-event
# fee or our fee for one show; { "share" => 0.0 } for our share of one show's
# ticket sales; "note" beside it on the contract. Empty means the deal as
# written. Stamped from the contract's draft at activation, so a moved date
# keeps its terms.
class AddContractTermsToShows < ActiveRecord::Migration[8.1]
  def change
    add_column :shows, :contract_terms, :jsonb, null: false, default: {}
  end
end

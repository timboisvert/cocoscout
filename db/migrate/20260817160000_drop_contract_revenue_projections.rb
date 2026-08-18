# frozen_string_literal: true

# The revenue projection feature (low/high ticket-price × tickets-sold guesses
# on a revenue-share contract) is retired — it never predicted anything and
# nothing reads it any more. Contracts show actuals from their shows instead.
class DropContractRevenueProjections < ActiveRecord::Migration[8.1]
  def change
    remove_column :contracts, :revenue_projections, :jsonb, default: {}
  end
end

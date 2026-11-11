# frozen_string_literal: true

# The price display choice is all or nothing (Tim, 2026-11-11): the all-in
# price ("$23.53 incl. taxes & fees"), or the ticket's own price with
# whatever a buyer pays on top named beside it ("$20.00 + taxes & fees").
# This morning's "before tax" kept the fees in the price, which read as
# neither.
class PricesShowAllInOrBeforeTaxesAndFees < ActiveRecord::Migration[8.1]
  def up
    change_column_default :ticketing_profiles, :price_display, from: "with_tax", to: "all_in"
    execute "UPDATE ticketing_profiles SET price_display = 'all_in' WHERE price_display = 'with_tax'"
    execute "UPDATE ticketing_profiles SET price_display = 'base' WHERE price_display = 'before_tax'"
  end

  def down
    change_column_default :ticketing_profiles, :price_display, from: "all_in", to: "with_tax"
    execute "UPDATE ticketing_profiles SET price_display = 'with_tax' WHERE price_display = 'all_in'"
    execute "UPDATE ticketing_profiles SET price_display = 'before_tax' WHERE price_display = 'base'"
  end
end

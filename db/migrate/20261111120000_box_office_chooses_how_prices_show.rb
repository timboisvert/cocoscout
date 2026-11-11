# frozen_string_literal: true

# How a box office shows its ticket prices (Tim, 2026-11-11): with the tax
# already in ("$16.54 incl. tax", as every page did), or before tax
# ("$15.00 + tax", the total a tap away). The fees a buyer pays are in the
# price either way.
class BoxOfficeChoosesHowPricesShow < ActiveRecord::Migration[8.1]
  def change
    add_column :ticketing_profiles, :price_display, :string, default: "with_tax", null: false
  end
end

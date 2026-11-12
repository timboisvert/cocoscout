# frozen_string_literal: true

# Who gets the tips rung up while nobody on the bar was on the clock (plan
# §9.14, Tim's pass of 2026-11-03): one choice per stretch of time, keyed by
# the stretch's first quarter hour: "house", "split", or a person's id.
class AddTipsUnstaffedToSettlementDays < ActiveRecord::Migration[8.0]
  def change
    add_column :settlement_days, :tips_unstaffed, :jsonb, default: {}, null: false
  end
end

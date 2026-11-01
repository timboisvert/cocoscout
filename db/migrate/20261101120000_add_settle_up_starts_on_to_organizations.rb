# frozen_string_literal: true

# Settle up's start date (Tim, 2026-11-01): days before it are history. The
# deploy sets every existing organization to the first of the month it runs
# in, and counts days since then that were already confirmed in Financials
# as settled (SettleUpStart.convert_all!). An organization made later has no
# start date: it has no history to hide.
class AddSettleUpStartsOnToOrganizations < ActiveRecord::Migration[8.1]
  def up
    add_column :organizations, :settle_up_starts_on, :date
    Organization.reset_column_information
    SettlementDay.reset_column_information
    SettleUpStart.convert_all!
  end

  def down
    remove_column :organizations, :settle_up_starts_on
  end
end

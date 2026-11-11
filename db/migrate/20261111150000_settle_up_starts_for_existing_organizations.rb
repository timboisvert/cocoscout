# frozen_string_literal: true

# The one-time switch for Settle up (Tim, 2026-11-01), run once every table
# it reads exists: each existing organization starts on the first of the
# month the deploy runs in, and days since then that were already confirmed
# in Financials, with nothing else in them, count as settled, so an
# organization that was caught up stays caught up. Only organizations with
# no start date are touched, so running it where the switch already
# happened changes nothing for them.
class SettleUpStartsForExistingOrganizations < ActiveRecord::Migration[8.1]
  def up
    [ Organization, SettlementDay ].each(&:reset_column_information)
    SettleUpStart.convert_all!
  end

  def down; end
end

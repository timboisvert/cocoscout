# frozen_string_literal: true

# Structured extras a contribution needs beyond label + amount. First use:
# worked-hours lines keep their ad-hoc "hours|role_id" pairs so discarding a
# draft run can rebuild the Pay People draft with full fidelity — hand-entered
# data (POS tips, typed hours) must never be lost to a discard.
class AddDetailsToPayoutContributions < ActiveRecord::Migration[8.1]
  def change
    add_column :payout_contributions, :details, :jsonb
  end
end

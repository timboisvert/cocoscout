# frozen_string_literal: true

# There is no organization-level payout calculation any more: a production
# chooses its own. So that nothing that pays today stops paying, every
# org-level default (production_id NULL) — and every legacy is_default flag —
# is mirrored, date for date, onto each of that org's productions that has no
# calculation of its own (see PayoutDefaultMigration). Then the org-level rows
# go and production_id becomes required.
class RetireOrgLevelPayoutDefaults < ActiveRecord::Migration[8.1]
  def up
    PayoutDefaultMigration.run!

    change_column_null :payout_scheme_defaults, :production_id, false
  end

  def down
    change_column_null :payout_scheme_defaults, :production_id, true
  end
end

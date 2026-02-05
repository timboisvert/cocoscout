# frozen_string_literal: true

class BackfillUserRolesForExistingCompanies < ActiveRecord::Migration[7.0]
  def up
    # No-op: This migration originally used Organization model which didn't exist yet.
    # The data has long since been backfilled through other means.
  end

  def down
    # No-op: do not remove roles
  end
end

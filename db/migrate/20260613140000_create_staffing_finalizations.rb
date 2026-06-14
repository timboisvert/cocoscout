# frozen_string_literal: true

# Tracks which weeks of the staffing schedule have been finalized for an org.
# Until a week is finalized, staff can't see their assignments (it's a draft);
# finalizing notifies assigned staff. One row per (organization, week_start).
class CreateStaffingFinalizations < ActiveRecord::Migration[8.1]
  def change
    create_table :staffing_finalizations do |t|
      t.references :organization, null: false, foreign_key: true
      t.date :week_start, null: false
      t.datetime :finalized_at
      t.references :finalized_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :staffing_finalizations, %i[organization_id week_start], unique: true
  end
end

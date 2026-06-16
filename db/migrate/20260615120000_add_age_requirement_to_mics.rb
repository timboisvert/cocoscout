# frozen_string_literal: true

class AddAgeRequirementToMics < ActiveRecord::Migration[8.1]
  def up
    # 0 = unknown (new default), 1 = all_ages, 2 = minimum (uses min_age)
    add_column :mics, :age_requirement, :integer, default: 0, null: false
    add_index :mics, :age_requirement

    # Backfill: only mics that were actually given an age keep one. A real
    # numeric min_age means a specific minimum; a manual min_age edit with no
    # number means the owner deliberately chose "all ages". Everything else
    # was just the old implicit default and becomes "unknown".
    execute <<~SQL.squish
      UPDATE mics SET age_requirement = 2 WHERE min_age IS NOT NULL
    SQL
    execute <<~SQL.squish
      UPDATE mics SET age_requirement = 1
      WHERE min_age IS NULL
        AND id IN (SELECT DISTINCT mic_id FROM mic_edits WHERE field = 'min_age')
    SQL
  end

  def down
    remove_column :mics, :age_requirement
  end
end

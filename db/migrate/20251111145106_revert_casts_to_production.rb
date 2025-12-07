# frozen_string_literal: true

class RevertCastsToProduction < ActiveRecord::Migration[8.1]
  def up
    # Remove call_to_audition_id from casts
    remove_column :casts, :call_to_audition_id
    remove_index :casts, :call_to_audition_id, if_exists: true
  end

  def down
    # Add back call_to_audition_id
    add_column :casts, :call_to_audition_id, :integer
    add_index :casts, :call_to_audition_id

    # Backfill
    execute <<-SQL
      UPDATE casts
      SET call_to_audition_id = (
        SELECT id FROM call_to_auditions
        WHERE call_to_auditions.production_id = casts.production_id
        LIMIT 1
      )
    SQL

    change_column_null :casts, :call_to_audition_id, false
  end
end

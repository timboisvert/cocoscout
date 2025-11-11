class MoveCastsToCallToAudition < ActiveRecord::Migration[8.1]
  def up
    # Add call_to_audition_id column
    add_column :casts, :call_to_audition_id, :integer
    add_index :casts, :call_to_audition_id

    # Backfill call_to_audition_id for existing casts
    execute <<-SQL
      UPDATE casts
      SET call_to_audition_id = (
        SELECT id FROM call_to_auditions
        WHERE call_to_auditions.production_id = casts.production_id
        LIMIT 1
      )
      WHERE call_to_audition_id IS NULL
        AND production_id IS NOT NULL
    SQL

    # Make call_to_audition_id non-nullable
    change_column_null :casts, :call_to_audition_id, false

    # Keep production_id for now (casts may still need direct production reference)
    # We'll decide later if we want to remove it completely
  end

  def down
    remove_column :casts, :call_to_audition_id
    remove_index :casts, :call_to_audition_id, if_exists: true
  end
end

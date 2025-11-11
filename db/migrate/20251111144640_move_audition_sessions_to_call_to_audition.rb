class MoveAuditionSessionsToCallToAudition < ActiveRecord::Migration[8.1]
  def up
    # First, backfill call_to_audition_id for existing sessions
    # that have production_id but no call_to_audition_id
    execute <<-SQL
      UPDATE audition_sessions
      SET call_to_audition_id = (
        SELECT id FROM call_to_auditions
        WHERE call_to_auditions.production_id = audition_sessions.production_id
        LIMIT 1
      )
      WHERE call_to_audition_id IS NULL
        AND production_id IS NOT NULL
    SQL

    # Make call_to_audition_id non-nullable
    change_column_null :audition_sessions, :call_to_audition_id, false

    # Remove the production_id column
    remove_column :audition_sessions, :production_id
    remove_index :audition_sessions, name: "index_audition_sessions_on_production_id", if_exists: true
  end

  def down
    # Add back production_id column
    add_column :audition_sessions, :production_id, :integer
    add_index :audition_sessions, :production_id

    # Backfill production_id from call_to_audition
    execute <<-SQL
      UPDATE audition_sessions
      SET production_id = (
        SELECT production_id FROM call_to_auditions
        WHERE call_to_auditions.id = audition_sessions.call_to_audition_id
      )
    SQL

    # Make production_id non-nullable
    change_column_null :audition_sessions, :production_id, false

    # Make call_to_audition_id nullable again
    change_column_null :audition_sessions, :call_to_audition_id, true
  end
end

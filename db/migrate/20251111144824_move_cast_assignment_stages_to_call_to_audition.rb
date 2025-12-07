# frozen_string_literal: true

class MoveCastAssignmentStagesToCallToAudition < ActiveRecord::Migration[8.1]
  def up
    # Add call_to_audition_id column
    add_column :cast_assignment_stages, :call_to_audition_id, :integer
    add_index :cast_assignment_stages, :call_to_audition_id

    # Backfill call_to_audition_id using production_id
    execute <<-SQL
      UPDATE cast_assignment_stages
      SET call_to_audition_id = (
        SELECT id FROM call_to_auditions
        WHERE call_to_auditions.production_id = cast_assignment_stages.production_id
        LIMIT 1
      )
      WHERE call_to_audition_id IS NULL
        AND production_id IS NOT NULL
    SQL

    # Make call_to_audition_id non-nullable
    change_column_null :cast_assignment_stages, :call_to_audition_id, false

    # Remove production_id column and its index
    remove_column :cast_assignment_stages, :production_id
    remove_index :cast_assignment_stages, name: 'index_cast_assignment_stages_on_production_id', if_exists: true
  end

  def down
    # Add back production_id column
    add_column :cast_assignment_stages, :production_id, :integer
    add_index :cast_assignment_stages, :production_id

    # Backfill production_id from call_to_audition
    execute <<-SQL
      UPDATE cast_assignment_stages
      SET production_id = (
        SELECT production_id FROM call_to_auditions
        WHERE call_to_auditions.id = cast_assignment_stages.call_to_audition_id
      )
    SQL

    # Make production_id non-nullable
    change_column_null :cast_assignment_stages, :production_id, false

    # Remove call_to_audition_id
    remove_column :cast_assignment_stages, :call_to_audition_id
    remove_index :cast_assignment_stages, :call_to_audition_id, if_exists: true
  end
end

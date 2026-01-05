class FixExistingAssignmentPositions < ActiveRecord::Migration[8.1]
  def up
    # Find all assignments with position = 0 and assign sequential positions
    # Group by show_id and role_id, then assign positions 1, 2, 3, etc.
    execute <<-SQL
      WITH ranked_assignments AS (
        SELECT id, show_id, role_id,
               ROW_NUMBER() OVER (PARTITION BY show_id, role_id ORDER BY created_at, id) as new_position
        FROM show_person_role_assignments
        WHERE position = 0
      )
      UPDATE show_person_role_assignments
      SET position = ranked_assignments.new_position
      FROM ranked_assignments
      WHERE show_person_role_assignments.id = ranked_assignments.id
    SQL
  end

  def down
    # Reversing this would lose position data, so we just reset to 0
    execute <<-SQL
      UPDATE show_person_role_assignments
      SET position = 0
    SQL
  end
end

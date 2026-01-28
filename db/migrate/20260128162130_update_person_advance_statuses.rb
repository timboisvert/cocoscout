class UpdatePersonAdvanceStatuses < ActiveRecord::Migration[8.1]
  def up
    # Update old status values to new terminology
    execute <<-SQL
      UPDATE person_advances
      SET status = 'partial'
      WHERE status = 'partially_recovered';
    SQL

    execute <<-SQL
      UPDATE person_advances
      SET status = 'settled'
      WHERE status = 'fully_recovered';
    SQL
  end

  def down
    # Revert to old status values
    execute <<-SQL
      UPDATE person_advances
      SET status = 'partially_recovered'
      WHERE status = 'partial';
    SQL

    execute <<-SQL
      UPDATE person_advances
      SET status = 'fully_recovered'
      WHERE status = 'settled';
    SQL
  end
end

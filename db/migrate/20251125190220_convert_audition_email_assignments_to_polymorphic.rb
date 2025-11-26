class ConvertAuditionEmailAssignmentsToPolymorphic < ActiveRecord::Migration[8.1]
  def up
    # Add polymorphic columns
    add_column :audition_email_assignments, :assignable_type, :string
    add_column :audition_email_assignments, :assignable_id, :integer

    # Migrate existing data
    execute <<-SQL
      UPDATE audition_email_assignments
      SET assignable_type = 'Person', assignable_id = person_id
      WHERE person_id IS NOT NULL
    SQL

    # Add index on polymorphic columns
    add_index :audition_email_assignments, [ :assignable_type, :assignable_id, :audition_cycle_id ],
              unique: true, name: 'index_audition_email_assignments_on_assignable_and_cycle'

    # Remove old person_id column and index
    remove_index :audition_email_assignments, name: 'index_audition_email_assignments_on_person_and_cycle', if_exists: true
    remove_column :audition_email_assignments, :person_id
  end

  def down
    # Add back person_id column
    add_column :audition_email_assignments, :person_id, :integer

    # Migrate data back for Person assignments only
    execute <<-SQL
      UPDATE audition_email_assignments
      SET person_id = assignable_id
      WHERE assignable_type = 'Person'
    SQL

    # Delete Group assignments as they can't be converted back
    execute <<-SQL
      DELETE FROM audition_email_assignments
      WHERE assignable_type = 'Group'
    SQL

    # Add back old index
    add_index :audition_email_assignments, [ :person_id, :audition_cycle_id ],
              unique: true, name: 'index_audition_email_assignments_on_person_and_cycle'

    # Remove polymorphic columns
    remove_index :audition_email_assignments, name: 'index_audition_email_assignments_on_assignable_and_cycle', if_exists: true
    remove_column :audition_email_assignments, :assignable_type
    remove_column :audition_email_assignments, :assignable_id
  end
end

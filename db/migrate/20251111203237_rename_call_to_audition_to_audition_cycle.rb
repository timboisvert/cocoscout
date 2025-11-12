class RenameCallToAuditionToAuditionCycle < ActiveRecord::Migration[8.1]
  def change
    # Temporarily remove the unique constraint
    remove_index :call_to_auditions, name: "index_call_to_auditions_on_production_id_and_active", if_exists: true

    # Rename the main table
    rename_table :call_to_auditions, :audition_cycles

    # Rename foreign key columns
    rename_column :audition_requests, :call_to_audition_id, :audition_cycle_id
    rename_column :audition_sessions, :call_to_audition_id, :audition_cycle_id
    rename_column :audition_email_assignments, :call_to_audition_id, :audition_cycle_id
    rename_column :cast_assignment_stages, :call_to_audition_id, :audition_cycle_id
    rename_column :email_groups, :call_to_audition_id, :audition_cycle_id

    # Rename other indexes
    rename_index :audition_cycles, 'index_call_to_auditions_on_production_id', 'index_audition_cycles_on_production_id'

    rename_index :audition_requests, 'index_audition_requests_on_call_to_audition_id', 'index_audition_requests_on_audition_cycle_id'
    rename_index :audition_sessions, 'index_audition_sessions_on_call_to_audition_id', 'index_audition_sessions_on_audition_cycle_id'
    rename_index :audition_email_assignments, 'index_audition_email_assignments_on_call_to_audition_id', 'index_audition_email_assignments_on_audition_cycle_id'
    rename_index :cast_assignment_stages, 'index_cast_assignment_stages_on_call_to_audition_id', 'index_cast_assignment_stages_on_audition_cycle_id'
    rename_index :email_groups, 'index_email_groups_on_call_to_audition_id', 'index_email_groups_on_audition_cycle_id'

    # Re-add the unique constraint with new name
    add_index :audition_cycles, [ :production_id, :active ], unique: true, where: "active = true", name: "index_audition_cycles_on_production_id_and_active"
  end
end

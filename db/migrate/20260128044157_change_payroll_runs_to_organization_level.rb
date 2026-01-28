class ChangePayrollRunsToOrganizationLevel < ActiveRecord::Migration[8.1]
  def change
    # Add organization reference to payroll_runs
    add_reference :payroll_runs, :organization, null: true, foreign_key: true

    # Migrate existing data: set organization based on production
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE payroll_runs
          SET organization_id = (
            SELECT organization_id FROM productions WHERE productions.id = payroll_runs.production_id
          )
        SQL
      end
    end

    # Make organization_id not null after migration
    change_column_null :payroll_runs, :organization_id, false

    # Remove production_id (keep for now with optional)
    change_column_null :payroll_runs, :production_id, true

    # Remove the index that includes production_id
    remove_index :payroll_runs, name: "idx_on_production_id_period_start_period_end_c55f4fba11"

    # Add new index on organization
    add_index :payroll_runs, [ :organization_id, :period_start, :period_end ]
  end
end

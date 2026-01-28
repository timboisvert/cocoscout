class RefactorPayrollScheduleForOrganization < ActiveRecord::Migration[8.1]
  def change
    # Add organization reference
    add_reference :payroll_schedules, :organization, null: true, foreign_key: true

    # Add new period configuration fields
    add_column :payroll_schedules, :period_type, :string, default: "biweekly", null: false
    add_column :payroll_schedules, :period_anchor, :date  # Reference date for period calculation
    add_column :payroll_schedules, :semi_monthly_days, :string  # e.g., "1,16" or "15,last"
    add_column :payroll_schedules, :payday_timing, :string, default: "period_end", null: false
    add_column :payroll_schedules, :payday_offset_days, :integer, default: 0  # Days after period end

    # Migrate existing data: copy production's organization_id to schedule
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE payroll_schedules
          SET organization_id = (
            SELECT organization_id FROM productions WHERE productions.id = payroll_schedules.production_id
          ),
          period_type = CASE frequency
            WHEN 'weekly' THEN 'weekly'
            WHEN 'biweekly' THEN 'biweekly'
            WHEN 'monthly' THEN 'monthly'
            ELSE 'biweekly'
          END,
          period_anchor = CURRENT_DATE,
          payday_timing = 'period_end'
        SQL
      end
    end

    # Make organization_id not null
    change_column_null :payroll_schedules, :organization_id, false

    # Make production_id optional (keeping for backwards compat)
    change_column_null :payroll_schedules, :production_id, true

    # Remove the unique index on production_id
    remove_index :payroll_schedules, :production_id

    # Make the organization_id index unique (it was already created by add_reference, just not unique)
    remove_index :payroll_schedules, :organization_id
    add_index :payroll_schedules, :organization_id, unique: true
  end
end

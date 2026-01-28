class RemoveActiveFromPayrollSchedules < ActiveRecord::Migration[8.1]
  def change
    remove_column :payroll_schedules, :active, :boolean
  end
end

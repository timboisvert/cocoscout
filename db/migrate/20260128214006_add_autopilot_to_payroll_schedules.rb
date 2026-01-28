class AddAutopilotToPayrollSchedules < ActiveRecord::Migration[8.1]
  def change
    add_column :payroll_schedules, :autopilot, :boolean, default: false, null: false
  end
end

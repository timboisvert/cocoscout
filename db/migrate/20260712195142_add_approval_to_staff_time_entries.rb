class AddApprovalToStaffTimeEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :staff_time_entries, :approved_at, :datetime
    add_reference :staff_time_entries, :approved_by, null: true,
                  foreign_key: { to_table: :users }
  end
end

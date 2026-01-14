class AddNotifyOnSubmissionToAuditionCycles < ActiveRecord::Migration[8.1]
  def change
    add_column :audition_cycles, :notify_on_submission, :boolean, default: false, null: false
  end
end

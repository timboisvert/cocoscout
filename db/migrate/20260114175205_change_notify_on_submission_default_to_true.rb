class ChangeNotifyOnSubmissionDefaultToTrue < ActiveRecord::Migration[8.1]
  def change
    change_column_default :audition_cycles, :notify_on_submission, from: false, to: true
  end
end

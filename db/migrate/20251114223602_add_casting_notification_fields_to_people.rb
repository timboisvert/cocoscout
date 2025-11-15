class AddCastingNotificationFieldsToPeople < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :casting_notification_sent_at, :datetime
    add_column :people, :notified_for_audition_cycle_id, :integer
  end
end

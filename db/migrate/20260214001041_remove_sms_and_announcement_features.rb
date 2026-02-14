class RemoveSmsAndAnnouncementFeatures < ActiveRecord::Migration[8.1]
  def change
    # Drop the sms_logs table
    drop_table :sms_logs, if_exists: true

    # Remove phone verification columns from users
    remove_column :users, :phone_pending_verification, :string, if_exists: true
    remove_column :users, :phone_verified_at, :datetime, if_exists: true
    remove_column :users, :phone_verification_code, :string, if_exists: true
    remove_column :users, :phone_verification_sent_at, :datetime, if_exists: true

    # Remove announcement dismissal column from users
    remove_column :users, :dismissed_announcements, :jsonb, if_exists: true

    # Delete SMS-related content templates
    reversible do |dir|
      dir.up do
        execute <<-SQL
          DELETE FROM content_templates
          WHERE key IN ('sms_show_cancellation', 'sms_vacancy_created', 'sms_vacancy_filled')
        SQL
      end
    end
  end
end

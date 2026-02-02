class RemoveUnusedEmailTemplates < ActiveRecord::Migration[8.1]
  # This migration removes email templates that are no longer used after the messaging overhaul:
  #
  # 1. availability_request - Removed in favor of in-app availability requests
  # 2. availability_request_group - Removed in favor of in-app availability requests
  #
  # Additionally, the following mailer code was removed (used raw views, not email templates):
  # - Manage::ContactMailer (entire mailer)
  # - Manage::PersonMailer#contact_email method
  # - All associated views in app/views/manage/contact_mailer/
  # - app/views/manage/person_mailer/contact_email.* views
  #
  # These "contact" emails are now handled via MessageService which creates in-app messages
  # and email notifications are sent via UnreadDigestJob.

  def up
    execute <<-SQL
      DELETE FROM email_templates
      WHERE key IN ('availability_request', 'availability_request_group')
    SQL
  end

  def down
    # Templates can be recreated via: rails db:seed:email_templates
    puts "Note: To restore removed templates, run: rails db:seed:email_templates"
  end
end

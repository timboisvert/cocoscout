class RemoveRequestAvailabilityEmailTemplates < ActiveRecord::Migration[8.1]
  def up
    # Remove the request_availability email templates
    execute <<-SQL
      DELETE FROM email_templates
      WHERE mailer_action IN ('request_availability', 'request_availability_for_group')
    SQL
  end

  def down
    # Re-create the email templates if rolling back
    # Note: This is a simplified version - the full templates would need to be recreated manually
    puts "Note: Email templates for request_availability were removed. They would need to be recreated manually."
  end
end

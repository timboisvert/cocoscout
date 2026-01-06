class RemoveAvailabilityRequestEmailTemplate < ActiveRecord::Migration[8.1]
  def up
    # Remove the availability_request email template
    execute <<-SQL
      DELETE FROM email_templates WHERE key = 'availability_request'
    SQL
  end

  def down
    # Template would need to be recreated manually via seeds
    puts "Note: availability_request email template was removed. Recreate via seeds if needed."
  end
end

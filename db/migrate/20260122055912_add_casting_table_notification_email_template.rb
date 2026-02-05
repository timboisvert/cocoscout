class AddCastingTableNotificationEmailTemplate < ActiveRecord::Migration[8.1]
  def up
    execute <<-SQL
      INSERT INTO email_templates (key, name, category, subject, description, template_type, mailer_class, mailer_action, body, available_variables, created_at, updated_at)
      VALUES (
        'casting_table_notification',
        'Casting Table Notification',
        'notification',
        'Cast Confirmation: {{production_names}}',
        'Notifies someone they''ve been cast through a casting table. Multiple productions may be listed.',
        'hybrid',
        'CastingTableMailer',
        'casting_notification',
        '<p>You have been cast for the following shows:</p>
{{shows_by_production}}
<p>Please let us know if you have any scheduling conflicts or questions.</p>',
        '[{"name":"production_names","description":"Comma-separated list of production names (e.g., ''Show A, Show B, and Show C'')"},{"name":"shows_by_production","description":"HTML sections with show dates grouped by production"}]',
        NOW(),
        NOW()
      )
      ON CONFLICT (key) DO NOTHING
    SQL
  end

  def down
    execute "DELETE FROM email_templates WHERE key = 'casting_table_notification'"
  end
end

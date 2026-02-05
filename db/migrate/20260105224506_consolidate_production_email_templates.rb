class ConsolidateProductionEmailTemplates < ActiveRecord::Migration[8.1]
  def up
    # Create the new consolidated template
    execute <<-SQL
      INSERT INTO email_templates (key, name, category, subject, description, template_type, mailer_class, mailer_action, body, available_variables, active, created_at, updated_at)
      VALUES (
        'production_message',
        'Production Message',
        'notification',
        '{{subject}}',
        'General-purpose email from production team to talent. Can be used for casting announcements, directory messages, or any production-related communication. Subject and body are fully customizable.',
        'passthrough',
        'Manage::ProductionMailer',
        'send_message',
        '{{body_content}}',
        '[{"name":"subject","description":"Custom email subject"},{"name":"body_content","description":"Custom HTML body content"}]',
        true,
        NOW(),
        NOW()
      )
      ON CONFLICT (key) DO NOTHING
    SQL

    # Delete the old templates
    execute "DELETE FROM email_templates WHERE key IN ('cast_email', 'contact_message')"
  end

  def down
    # Recreate the original templates
    execute <<-SQL
      INSERT INTO email_templates (key, name, category, subject, description, template_type, mailer_class, mailer_action, body, available_variables, active, created_at, updated_at)
      VALUES (
        'cast_email',
        'Cast Email (Free-form)',
        'notification',
        '{{subject}}',
        'Generic casting-related email with fully customizable content.',
        'passthrough',
        'Manage::CastingMailer',
        'cast_email',
        '{{body_content}}',
        '[{"name":"subject","description":"Custom email subject"},{"name":"body_content","description":"Custom HTML body content"}]',
        true,
        NOW(),
        NOW()
      )
      ON CONFLICT (key) DO NOTHING
    SQL

    execute <<-SQL
      INSERT INTO email_templates (key, name, category, subject, description, template_type, mailer_class, mailer_action, body, available_variables, active, created_at, updated_at)
      VALUES (
        'contact_message',
        'Contact Message',
        'marketing',
        '{{subject}}',
        'General-purpose contact email from producers to talent. The subject and body are fully customizable.',
        'passthrough',
        'Manage::ContactMailer',
        'send_message',
        '{{body_content}}',
        '[{"name":"subject","description":"Custom email subject"},{"name":"body_content","description":"Custom HTML body content"}]',
        true,
        NOW(),
        NOW()
      )
      ON CONFLICT (key) DO NOTHING
    SQL

    # Delete the consolidated template
    execute "DELETE FROM email_templates WHERE key = 'production_message'"
  end
end

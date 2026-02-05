class CreateSignUpRegistrationNotificationEmailTemplate < ActiveRecord::Migration[8.1]
  def up
    execute <<-SQL
      INSERT INTO email_templates (key, name, category, subject, description, template_type, mailer_class, mailer_action, prepend_production_name, active, body, created_at, updated_at)
      VALUES (
        'sign_up_registration_notification',
        'Sign-Up Registration Received',
        'notification',
        'New sign-up from {{registrant_name}}',
        'Notifies production team when someone registers for a sign-up form.',
        'structured',
        'Manage::SignUpMailer',
        'registration_notification',
        true,
        true,
        '<p>Hello {{recipient_name}},</p>
<p>A new registration has been submitted for <strong>{{sign_up_form_name}}</strong>.</p>
<p><strong>From:</strong> {{registrant_name}}</p>
<p><strong>Slot:</strong> {{slot_name}}</p>
{{#event_info}}
<p><strong>Event:</strong> {{event_info}}</p>
{{/event_info}}
<p><a href="{{registrations_url}}">View Registrations</a></p>',
        NOW(),
        NOW()
      )
      ON CONFLICT (key) DO NOTHING
    SQL
  end

  def down
    execute "DELETE FROM email_templates WHERE key = 'sign_up_registration_notification'"
  end
end

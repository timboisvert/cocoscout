# frozen_string_literal: true

class CreateSignUpRegistrantEmailTemplates < ActiveRecord::Migration[8.1]
  def up
    # Sign-up confirmation - when user registers for a slot
    execute <<-SQL
      INSERT INTO email_templates (key, name, category, subject, description, template_type, mailer_class, mailer_action, prepend_production_name, active, body, created_at, updated_at)
      VALUES (
        'sign_up_confirmation',
        'Sign-Up Confirmation',
        'confirmation',
        'You''re signed up for {{sign_up_form_name}}',
        'Sent to registrants when they successfully sign up for a slot.',
        'structured',
        'SignUpRegistrantMailer',
        'confirmation',
        true,
        true,
        '<p>Hi {{registrant_name}},</p>
<p>You''re confirmed for <strong>{{sign_up_form_name}}</strong>!</p>
<p><strong>Slot:</strong> {{slot_name}}</p>
<p><strong>Show:</strong> {{show_name}}</p>
<p><strong>Date:</strong> {{show_date}}</p>
<p>If you need to make changes or cancel your registration, you can do so from your account.</p>',
        NOW(),
        NOW()
      )
      ON CONFLICT (key) DO NOTHING
    SQL

    # Sign-up queued - when user joins the queue (admin_assigns mode)
    execute <<-SQL
      INSERT INTO email_templates (key, name, category, subject, description, template_type, mailer_class, mailer_action, prepend_production_name, active, body, created_at, updated_at)
      VALUES (
        'sign_up_queued',
        'Sign-Up Queued',
        'confirmation',
        'You''ve joined the queue for {{sign_up_form_name}}',
        'Sent to registrants when they are added to the queue awaiting slot assignment.',
        'structured',
        'SignUpRegistrantMailer',
        'queued',
        true,
        true,
        '<p>Hi {{registrant_name}},</p>
<p>You''ve been added to the queue for <strong>{{sign_up_form_name}}</strong>.</p>
<p><strong>Show:</strong> {{show_name}}</p>
<p><strong>Date:</strong> {{show_date}}</p>
<p>The production team will assign you to a slot. You''ll receive another email when your slot is confirmed.</p>',
        NOW(),
        NOW()
      )
      ON CONFLICT (key) DO NOTHING
    SQL

    # Sign-up slot assigned - when moved from queue to slot
    execute <<-SQL
      INSERT INTO email_templates (key, name, category, subject, description, template_type, mailer_class, mailer_action, prepend_production_name, active, body, created_at, updated_at)
      VALUES (
        'sign_up_slot_assigned',
        'Sign-Up Slot Assigned',
        'notification',
        'You''ve been assigned a slot for {{sign_up_form_name}}',
        'Sent to registrants when they are moved from the queue to a specific slot.',
        'structured',
        'SignUpRegistrantMailer',
        'slot_assigned',
        true,
        true,
        '<p>Hi {{registrant_name}},</p>
<p>Great news! You''ve been assigned a slot for <strong>{{sign_up_form_name}}</strong>.</p>
<p><strong>Slot:</strong> {{slot_name}}</p>
<p><strong>Show:</strong> {{show_name}}</p>
<p><strong>Date:</strong> {{show_date}}</p>
<p>If you need to make changes or cancel your registration, you can do so from your account.</p>',
        NOW(),
        NOW()
      )
      ON CONFLICT (key) DO NOTHING
    SQL

    # Sign-up slot changed - when user modifies their slot
    execute <<-SQL
      INSERT INTO email_templates (key, name, category, subject, description, template_type, mailer_class, mailer_action, prepend_production_name, active, body, created_at, updated_at)
      VALUES (
        'sign_up_slot_changed',
        'Sign-Up Slot Changed',
        'notification',
        'Your slot has been changed for {{sign_up_form_name}}',
        'Sent to registrants when they change their slot selection.',
        'structured',
        'SignUpRegistrantMailer',
        'slot_changed',
        true,
        true,
        '<p>Hi {{registrant_name}},</p>
<p>Your registration for <strong>{{sign_up_form_name}}</strong> has been updated.</p>
<p><strong>New Slot:</strong> {{slot_name}}</p>
<p><strong>Show:</strong> {{show_name}}</p>
<p><strong>Date:</strong> {{show_date}}</p>
<p>If you have any questions, please contact the production team.</p>',
        NOW(),
        NOW()
      )
      ON CONFLICT (key) DO NOTHING
    SQL

    # Sign-up cancelled - when user cancels their registration
    execute <<-SQL
      INSERT INTO email_templates (key, name, category, subject, description, template_type, mailer_class, mailer_action, prepend_production_name, active, body, created_at, updated_at)
      VALUES (
        'sign_up_cancelled',
        'Sign-Up Cancelled',
        'notification',
        'Your sign-up has been cancelled',
        'Sent to registrants when their registration is cancelled.',
        'structured',
        'SignUpRegistrantMailer',
        'cancelled',
        true,
        true,
        '<p>Hi {{registrant_name}},</p>
<p>Your registration for <strong>{{sign_up_form_name}}</strong> has been cancelled.</p>
<p><strong>Show:</strong> {{show_name}}</p>
<p><strong>Date:</strong> {{show_date}}</p>
<p>If this was a mistake or you''d like to sign up again, please visit the sign-up page.</p>',
        NOW(),
        NOW()
      )
      ON CONFLICT (key) DO NOTHING
    SQL
  end

  def down
    execute "DELETE FROM email_templates WHERE key IN ('sign_up_confirmation', 'sign_up_queued', 'sign_up_slot_assigned', 'sign_up_slot_changed', 'sign_up_cancelled')"
  end
end

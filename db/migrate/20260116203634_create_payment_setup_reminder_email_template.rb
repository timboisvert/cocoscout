# frozen_string_literal: true

class CreatePaymentSetupReminderEmailTemplate < ActiveRecord::Migration[8.1]
  def up
    execute <<-SQL
      INSERT INTO email_templates (key, name, category, subject, description, template_type, mailer_class, mailer_action, prepend_production_name, active, body, available_variables, created_at, updated_at)
      VALUES (
        'payment_setup_reminder',
        'Payment Setup Reminder',
        'reminder',
        'Please set up your payment information',
        'Sent to talent pool members who haven''t configured their payment info (Venmo or Zelle) for payouts.',
        'hybrid',
        'Manage::PaymentMailer',
        'payment_setup_reminder',
        true,
        true,
        '<p>We would like to send you payment for your recent work with <strong>{{production_name}}</strong>, but we do not have your payment information on file yet.</p>
<p>Please take a moment to set up your Venmo or Zelle details so we can process your payout:</p>
<p><a href="{{payment_setup_url}}">Set Up Payment Info</a></p>
<p>If you have any questions, feel free to reach out to the production team.</p>',
        '[{"name":"production_name","description":"Name of the production"},{"name":"payment_setup_url","description":"URL to the payment setup page"}]',
        NOW(),
        NOW()
      )
      ON CONFLICT (key) DO NOTHING
    SQL
  end

  def down
    execute "DELETE FROM email_templates WHERE key = 'payment_setup_reminder'"
  end
end

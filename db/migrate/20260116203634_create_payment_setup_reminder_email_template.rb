# frozen_string_literal: true

class CreatePaymentSetupReminderEmailTemplate < ActiveRecord::Migration[8.1]
  def up
    EmailTemplate.create!(
      key: "payment_setup_reminder",
      name: "Payment Setup Reminder",
      category: "reminder",
      subject: "Please set up your payment information",
      description: "Sent to talent pool members who haven't configured their payment info (Venmo or Zelle) for payouts.",
      template_type: "hybrid",
      mailer_class: "Manage::PaymentMailer",
      mailer_action: "payment_setup_reminder",
      prepend_production_name: true,
      active: true,
      body: <<~HTML,
        <p>We would like to send you payment for your recent work with <strong>{{production_name}}</strong>, but we do not have your payment information on file yet.</p>
        <p>Please take a moment to set up your Venmo or Zelle details so we can process your payout:</p>
        <p><a href="{{payment_setup_url}}">Set Up Payment Info</a></p>
        <p>If you have any questions, feel free to reach out to the production team.</p>
      HTML
      available_variables: [
        { name: "production_name", description: "Name of the production" },
        { name: "payment_setup_url", description: "URL to the payment setup page" }
      ]
    )
  end

  def down
    EmailTemplate.find_by(key: "payment_setup_reminder")&.destroy
  end
end

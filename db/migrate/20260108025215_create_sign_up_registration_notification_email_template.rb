class CreateSignUpRegistrationNotificationEmailTemplate < ActiveRecord::Migration[8.1]
  def up
    EmailTemplate.create!(
      key: "sign_up_registration_notification",
      name: "Sign-Up Registration Received",
      category: "notification",
      subject: "New sign-up from {{registrant_name}}",
      description: "Notifies production team when someone registers for a sign-up form.",
      template_type: "structured",
      mailer_class: "Manage::SignUpMailer",
      mailer_action: "registration_notification",
      prepend_production_name: true,
      active: true,
      body: <<~HTML
        <p>Hello {{recipient_name}},</p>
        <p>A new registration has been submitted for <strong>{{sign_up_form_name}}</strong>.</p>
        <p><strong>From:</strong> {{registrant_name}}</p>
        <p><strong>Slot:</strong> {{slot_name}}</p>
        {{#event_info}}
        <p><strong>Event:</strong> {{event_info}}</p>
        {{/event_info}}
        <p><a href="{{registrations_url}}">View Registrations</a></p>
      HTML
    )
  end

  def down
    EmailTemplate.find_by(key: "sign_up_registration_notification")&.destroy
  end
end

# frozen_string_literal: true

class CreateSignUpRegistrantEmailTemplates < ActiveRecord::Migration[8.1]
  def up
    # Sign-up confirmation - when user registers for a slot
    EmailTemplate.create!(
      key: "sign_up_confirmation",
      name: "Sign-Up Confirmation",
      category: "confirmation",
      subject: "You're signed up for {{sign_up_form_name}}",
      description: "Sent to registrants when they successfully sign up for a slot.",
      template_type: "structured",
      mailer_class: "SignUpRegistrantMailer",
      mailer_action: "confirmation",
      prepend_production_name: true,
      active: true,
      body: <<~HTML
        <p>Hi {{registrant_name}},</p>
        <p>You're confirmed for <strong>{{sign_up_form_name}}</strong>!</p>
        <p><strong>Slot:</strong> {{slot_name}}</p>
        <p><strong>Show:</strong> {{show_name}}</p>
        <p><strong>Date:</strong> {{show_date}}</p>
        <p>If you need to make changes or cancel your registration, you can do so from your account.</p>
      HTML
    )

    # Sign-up queued - when user joins the queue (admin_assigns mode)
    EmailTemplate.create!(
      key: "sign_up_queued",
      name: "Sign-Up Queued",
      category: "confirmation",
      subject: "You've joined the queue for {{sign_up_form_name}}",
      description: "Sent to registrants when they are added to the queue awaiting slot assignment.",
      template_type: "structured",
      mailer_class: "SignUpRegistrantMailer",
      mailer_action: "queued",
      prepend_production_name: true,
      active: true,
      body: <<~HTML
        <p>Hi {{registrant_name}},</p>
        <p>You've been added to the queue for <strong>{{sign_up_form_name}}</strong>.</p>
        <p><strong>Show:</strong> {{show_name}}</p>
        <p><strong>Date:</strong> {{show_date}}</p>
        <p>The production team will assign you to a slot. You'll receive another email when your slot is confirmed.</p>
      HTML
    )

    # Sign-up slot assigned - when moved from queue to slot
    EmailTemplate.create!(
      key: "sign_up_slot_assigned",
      name: "Sign-Up Slot Assigned",
      category: "notification",
      subject: "You've been assigned a slot for {{sign_up_form_name}}",
      description: "Sent to registrants when they are moved from the queue to a specific slot.",
      template_type: "structured",
      mailer_class: "SignUpRegistrantMailer",
      mailer_action: "slot_assigned",
      prepend_production_name: true,
      active: true,
      body: <<~HTML
        <p>Hi {{registrant_name}},</p>
        <p>Great news! You've been assigned a slot for <strong>{{sign_up_form_name}}</strong>.</p>
        <p><strong>Slot:</strong> {{slot_name}}</p>
        <p><strong>Show:</strong> {{show_name}}</p>
        <p><strong>Date:</strong> {{show_date}}</p>
        <p>If you need to make changes or cancel your registration, you can do so from your account.</p>
      HTML
    )

    # Sign-up slot changed - when user modifies their slot
    EmailTemplate.create!(
      key: "sign_up_slot_changed",
      name: "Sign-Up Slot Changed",
      category: "notification",
      subject: "Your slot has been changed for {{sign_up_form_name}}",
      description: "Sent to registrants when they change their slot selection.",
      template_type: "structured",
      mailer_class: "SignUpRegistrantMailer",
      mailer_action: "slot_changed",
      prepend_production_name: true,
      active: true,
      body: <<~HTML
        <p>Hi {{registrant_name}},</p>
        <p>Your registration for <strong>{{sign_up_form_name}}</strong> has been updated.</p>
        <p><strong>New Slot:</strong> {{slot_name}}</p>
        <p><strong>Show:</strong> {{show_name}}</p>
        <p><strong>Date:</strong> {{show_date}}</p>
        <p>If you have any questions, please contact the production team.</p>
      HTML
    )

    # Sign-up cancelled - when user cancels their registration
    EmailTemplate.create!(
      key: "sign_up_cancelled",
      name: "Sign-Up Cancelled",
      category: "notification",
      subject: "Your sign-up has been cancelled",
      description: "Sent to registrants when their registration is cancelled.",
      template_type: "structured",
      mailer_class: "SignUpRegistrantMailer",
      mailer_action: "cancelled",
      prepend_production_name: true,
      active: true,
      body: <<~HTML
        <p>Hi {{registrant_name}},</p>
        <p>Your registration for <strong>{{sign_up_form_name}}</strong> has been cancelled.</p>
        <p><strong>Show:</strong> {{show_name}}</p>
        <p><strong>Date:</strong> {{show_date}}</p>
        <p>If this was a mistake or you'd like to sign up again, please visit the sign-up page.</p>
      HTML
    )
  end

  def down
    EmailTemplate.where(key: %w[
      sign_up_confirmation
      sign_up_queued
      sign_up_slot_assigned
      sign_up_slot_changed
      sign_up_cancelled
    ]).destroy_all
  end
end

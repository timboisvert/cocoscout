# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:deletion)

    # Seed content templates after database is cleaned
    seed_content_templates
  end

  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.start
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end
end

def seed_content_templates
  templates = [
    { key: "auth_welcome", name: "Welcome Email", subject: "Welcome to CocoScout", body: "Hello {{ recipient_name }}", category: "authentication", channel: "email" },
    { key: "auth_password_reset", name: "Password Reset", subject: "Reset", body: "Reset: {{ reset_url }}", category: "authentication", channel: "email" },
    { key: "person_invitation", name: "Person Invitation", subject: "Invited", body: "You're invited", category: "invitations", channel: "email" },
    { key: "group_invitation", name: "Group Invitation", subject: "Group Invite", body: "Join group", category: "invitations", channel: "email" },
    { key: "shoutout_invitation", name: "Shoutout Invitation", subject: "Shoutout", body: "Shoutout!", category: "social", channel: "email" },
    { key: "team_organization_invitation", name: "Org Invitation", subject: "Team Invite", body: "Join", category: "invitations", channel: "email" },
    { key: "team_production_invitation", name: "Production Invitation", subject: "Production Invite", body: "Join", category: "invitations", channel: "email" },
    { key: "audition_invitation", name: "Audition Invitation", subject: "Audition", body: "Audition invite", category: "auditions", channel: "message" },
    { key: "audition_not_invited", name: "Not Invited", subject: "Update", body: "Thanks", category: "auditions", channel: "message" },
    { key: "audition_added_to_cast", name: "Added to Cast", subject: "Cast!", body: "You're cast", category: "casting", channel: "message" },
    { key: "audition_not_cast", name: "Not Cast", subject: "Update", body: "Thanks", category: "casting", channel: "message" },
    { key: "vacancy_invitation", name: "Vacancy Invitation", subject: "Opening", body: "Vacancy", category: "vacancies", channel: "both" },
    { key: "vacancy_created", name: "Vacancy Created", subject: "Vacancy", body: "New vacancy", category: "vacancies", channel: "both" },
    { key: "vacancy_filled", name: "Vacancy Filled", subject: "Filled", body: "Vacancy filled", category: "vacancies", channel: "both" },
    { key: "vacancy_reclaimed", name: "Vacancy Reclaimed", subject: "Reclaimed", body: "Reclaimed", category: "vacancies", channel: "both" },
    { key: "show_canceled", name: "Show Canceled", subject: "Canceled", body: "Show canceled", category: "shows", channel: "both" },
    { key: "sign_up_confirmation", name: "Sign-Up Confirmation", subject: "Confirmed", body: "Confirmed", category: "sign_ups", channel: "message" },
    { key: "sign_up_queued", name: "Sign-Up Queued", subject: "Waitlisted", body: "Waitlisted", category: "sign_ups", channel: "message" },
    { key: "sign_up_slot_assigned", name: "Slot Assigned", subject: "Assigned", body: "Assigned", category: "sign_ups", channel: "message" },
    { key: "sign_up_slot_changed", name: "Slot Changed", subject: "Changed", body: "Changed", category: "sign_ups", channel: "message" },
    { key: "sign_up_cancelled", name: "Sign-Up Cancelled", subject: "Cancelled", body: "Cancelled", category: "sign_ups", channel: "message" },
    { key: "sign_up_registration_notification", name: "Registration Notification", subject: "New signup", body: "New signup", category: "sign_ups", channel: "message" },
    { key: "unread_digest", name: "Unread Digest", subject: "Unread messages", body: "Check inbox", category: "messaging", channel: "email" },
    { key: "group_member_added", name: "Member Added", subject: "Added", body: "Added to group", category: "groups", channel: "message" },
    { key: "shoutout_notification", name: "Shoutout Notification", subject: "Shoutout", body: "You got a shoutout", category: "social", channel: "message" },
    { key: "audition_request_submitted", name: "Request Submitted", subject: "Received", body: "Request received", category: "auditions", channel: "message" },
    { key: "talent_left_production", name: "Talent Left", subject: "Left", body: "Talent left", category: "casting", channel: "message" },
    { key: "questionnaire_invitation", name: "Questionnaire", subject: "Questionnaire", body: "Please complete", category: "questionnaires", channel: "message" },
    { key: "cast_notification", name: "Cast Notification", subject: "Cast", body: "You're cast", category: "casting", channel: "message" },
    { key: "removed_from_cast_notification", name: "Removed from Cast", subject: "Removed", body: "Removed", category: "casting", channel: "message" },
    { key: "casting_table_notification", name: "Casting Table", subject: "Casting", body: "Casting info", category: "casting", channel: "message" },
    { key: "payment_setup_reminder", name: "Payment Reminder", subject: "Payment", body: "Set up payment", category: "payments", channel: "message" }
  ]

  templates.each do |attrs|
    ContentTemplate.find_or_create_by!(key: attrs[:key]) do |t|
      t.name = attrs[:name]
      t.subject = attrs[:subject]
      t.body = attrs[:body]
      t.category = attrs[:category]
      t.channel = attrs[:channel]
      t.active = true
    end
  end
end

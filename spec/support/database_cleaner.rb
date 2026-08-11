# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:deletion)

    # Seed content templates after database is cleaned
    seed_content_templates
  end

  # Examples tagged `no_transaction: true` (threaded/concurrency tests) commit
  # for real so other DB connections can see their rows; they're cleaned by
  # deletion instead. Pair the tag with `uses_transaction "<example name>"` so
  # rspec-rails fixture wrapping stays out of the way too.
  config.before(:each) do |example|
    DatabaseCleaner.strategy = example.metadata[:no_transaction] ? :deletion : :transaction
    DatabaseCleaner.start
  end

  config.after(:each) do |example|
    DatabaseCleaner.clean
    # Deletion wipes every table, including the templates seeded before(:suite).
    seed_content_templates if example.metadata[:no_transaction]
  end
end

def seed_content_templates
  templates = [
    { key: "auth_welcome", name: "Welcome Email", subject: "Welcome to CocoScout", body: "Hello {{ recipient_name }}", category: "authentication", channel: "email" },
    { key: "auth_password_reset", name: "Password Reset", subject: "Reset", body: "Reset: {{ reset_url }}", category: "authentication", channel: "email" },
    { key: "person_invitation", name: "Person Invitation", subject: "You've been invited to join {{organization_name}} on CocoScout", body: "<p>{{organization_name}} is using CocoScout. <a href=\"{{setup_url}}\">Set Up Your Account</a></p>", category: "invitations", channel: "email" },
    { key: "contract_person_added", name: "Added to a Contract", subject: "{{organization_name}} added you to a contract", body: "<p>{{organization_name}} has set you up on a contract in CocoScout. <a href=\"{{contracts_url}}\">View your contracts</a>.</p>", category: "invitations", channel: "message" },
    { key: "group_invitation", name: "Group Invitation", subject: "Group Invite", body: "Join group", category: "invitations", channel: "email" },
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
    { key: "audition_request_submitted", name: "Request Submitted", subject: "Received", body: "Request received", category: "auditions", channel: "message" },
    { key: "talent_left_production", name: "Talent Left", subject: "Left", body: "Talent left", category: "casting", channel: "message" },
    { key: "questionnaire_invitation", name: "Questionnaire", subject: "Questionnaire", body: "Please complete", category: "questionnaires", channel: "message" },
    { key: "cast_notification", name: "Cast Notification", subject: "Cast", body: "You're cast", category: "casting", channel: "message" },
    { key: "removed_from_cast_notification", name: "Removed from Cast", subject: "Removed", body: "Removed", category: "casting", channel: "message" },
    { key: "casting_table_notification", name: "Casting Table", subject: "Casting", body: "Casting info", category: "casting", channel: "message" },
    { key: "payment_setup_reminder", name: "Payment Reminder", subject: "Payment", body: "Set up payment", category: "payments", channel: "message" },
    { key: "payout_sent_to_payee", name: "Payout Sent — on its way (payee)",
      subject: "{{amount}} is on its way from {{organization_name}}",
      body: "<p>Hi {{recipient_name}},</p><p>{{organization_name}} just sent you {{amount}}.</p>" \
            "<p>It should reach your bank account {{expected_window}}.</p>" \
            "<p><a href=\"{{payments_url}}\">View this payment in My Payments</a></p>",
      category: "payments", channel: "both" },
    { key: "payout_sent_to_payee_first_payment", name: "Payout Sent — first payment (payee)",
      subject: "{{amount}} is on its way from {{organization_name}}",
      body: "<p>Hi {{recipient_name}},</p><p>{{organization_name}} just sent you {{amount}} — your first payment through CocoScout.</p>" \
            "<p>First payments take a bit longer than usual: our payout provider needs extra time to finish setting up your account. Expect this one {{expected_window}}.</p>" \
            "<p><a href=\"{{payments_url}}\">View this payment in My Payments</a></p>",
      category: "payments", channel: "both" },
    { key: "payout_sent_to_payee_no_bank", name: "Payout Sent — waiting on a bank account (payee)",
      subject: "{{amount}} from {{organization_name}} is waiting for you",
      body: "<p>Hi {{recipient_name}},</p><p>{{organization_name}} has {{amount}} set aside for you.</p>" \
            "<p>We can't send it yet — there's no bank account on your profile. Add one and your money will be on its way.</p>" \
            "<p><a href=\"{{setup_url}}\">Add your bank account</a></p>",
      category: "payments", channel: "both" },
    { key: "staff_onboarding_invite", name: "Staff Onboarding Invite", subject: "Welcome to {{organization_name}}", body: "Hi {{first_name}}, get set up at {{onboarding_url}}", category: "staffing", channel: "both" },
    # Migration-owned templates still need seeding here — the cleaner truncates
    # and re-seeds from this list, so anything a job renders must be present.
    { key: "contract_signature_nudge", name: "Contract Signature Reminder",
      subject: "Reminder: your {{organization_name}} contract is waiting",
      body: "<p>Hi {{recipient_name}}, sign by {{deadline}}.</p><p><a href=\"{{sign_url}}\">Sign</a></p>",
      category: "contracts", channel: "both" },
    { key: "contract_signature_expired", name: "Contract Signature Expired",
      subject: "Your {{organization_name}} contract has expired",
      body: "<p>Hi {{recipient_name}}, the contract for {{production_name}} expired.</p>",
      category: "contracts", channel: "both" },
    { key: "contract_countersigned_to_signer", name: "Contract Fully Signed (counterparty copy)",
      subject: "Signed: your {{organization_name}} contract for {{production_name}}",
      body: "<p>Hi {{recipient_name}}, signed by both of you on {{signed_on}}. A copy is attached. <a href=\"{{contracts_url}}\">Your contracts</a>.</p>",
      category: "contracts", channel: "both" },
    { key: "contract_signature_stalled_manager", name: "Contract Still Unsigned (manager)",
      subject: "{{contractor_name}} hasn't signed yet",
      body: "<p>{{contractor_name}} — {{production_name}} not signed. They have until {{deadline}}.</p><p><a href=\"{{contract_url}}\">Open</a></p>",
      category: "contracts", channel: "message" },
    { key: "contract_signature_expired_manager", name: "Contract Signature Expired (manager)",
      subject: "{{contractor_name}}'s contract expired without being signed",
      body: "<p>{{contractor_name}} — {{production_name}} expired on {{deadline}}.</p><p><a href=\"{{contract_url}}\">Open</a></p>",
      category: "contracts", channel: "message" },
    { key: "payout_returned_manager", name: "Payout Returned (manager)",
      subject: "{{amount}} to {{payee_name}} came back",
      body: "<p>{{amount}} to {{payee_name}} was returned.</p><p><a href=\"{{payout_run_url}}\">View</a></p>",
      category: "payments", channel: "message" },
    { key: "payout_returned_to_payee", name: "Payout Returned (payee)",
      subject: "We couldn't get {{amount}} into your bank account",
      body: "<p>Hi {{recipient_name}}, {{organization_name}} sent {{amount}} but it came back.</p><p><a href=\"{{setup_url}}\">Check details</a></p>",
      category: "payments", channel: "both" },
    { key: "payout_funding_failed", name: "Payout Funding Failed",
      subject: "The debit for your {{total}} payout run didn't go through",
      body: "<p>The debit for {{total}} to {{people_count}} was declined.</p><p><a href=\"{{payout_run_url}}\">View</a></p>",
      category: "payments", channel: "both" },
    { key: "payout_auto_retry_paid", name: "Payout Auto-Retry Paid",
      subject: "{{total}} paid automatically on your payout run",
      body: "<p>{{people}} connected a bank, so we sent {{total}}.</p><p><a href=\"{{payout_run_url}}\">View</a></p>",
      category: "payments", channel: "message" },
    { key: "shift_declined_manager", name: "Shift Declined (manager alert)",
      subject: "{{person_name}} can't make a shift",
      body: "<p>{{person_name}} can't make their <strong>{{role_name}}</strong> shift on <strong>{{shift_time}}</strong>.</p>" \
            "{{#decline_reason}}<p>Their note: “{{decline_reason}}”</p>{{/decline_reason}}" \
            "<p><a href=\"{{scheduling_url}}\">View that day in Staffing Scheduling</a></p>",
      category: "staffing", channel: "message" },
    { key: "staff_schedule_notification", name: "Staff Schedule Notification", subject: "Your work schedule — week of {{week_label}}", body: "<p>{{intro}}</p>{{shifts_list}} See your <a href=\"{{my_shifts_link}}\">My Shifts</a>.", category: "shows", channel: "message" },
    { key: "course_registration_confirmed", name: "Course Registration Confirmed", subject: "You're registered for {{course_title}}!", body: "Hi {{recipient_name}}, your registration for {{course_title}} is confirmed.", category: "courses", channel: "both" },
    { key: "course_registration_producer_notification", name: "Course Registration Producer Notification", subject: "New registration for {{course_title}}", body: "{{registrant_name}} has registered for {{course_title}}.", category: "courses", channel: "message" }
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

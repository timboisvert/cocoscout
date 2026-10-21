# frozen_string_literal: true

# The few groups a person sets Push and Email for (Account settings →
# Notifications). The Notifications list always shows everything.
#
# live: whether anything sends into the group yet (every area since
# 2026-10-20; V1.1 plan §9). A group's Push switch only shows when it's live,
# so no switch promises what nothing does.
# email: :person (the person's own switch), :plan (the organization picks, by
# plan: Ticketing settings → Notifications, Tim 2026-10-20), :always (it
# always goes: it carries a link they need) or nil (no email).
# legacy_email: the older preference keys this group's Email switch stands
# for, so emails that read them keep honoring the person's choice.
module NotificationGroups
  Group = Data.define(:key, :label, :description, :section, :push_default, :email, :email_default, :live, :legacy_email, :area) do
    def email_by_plan? = email == :plan
    def ticketing? = section == :ticketing
  end

  ALL = [
    Group.new("casting", "Casting and vacancies", "You're cast, a show changes, someone needs cover.", :yours, true, :person, true, true, %w[vacancy_invitations vacancy_notifications], "Casting"),
    Group.new("signups", "Sign-ups and auditions", "Spots, results, invitations to audition, reminders before a deadline.", :yours, true, :person, true, true, %w[audition_invitations], "Sign-ups"),
    Group.new("invitations", "Invitations", "To join a group or a production team, or to answer a questionnaire.", :yours, true, :person, true, true, %w[group_invitations], nil),
    Group.new("pay", "Pay and payouts", "Your pay on its way or sent back; for managers, payout runs that bounce, come back or pay by themselves.", :yours, true, :person, true, true, [], "Pay"),
    # Email always goes for contracts: it carries the signing link or the signed copy.
    Group.new("contracts", "Contracts", "Requests and reminders to sign, signed and countersigned, and ones that stall or expire.", :yours, true, :always, true, true, [], "Contracts"),
    Group.new("shifts", "Shifts and hours", "Shifts assigned, hours approved, onboarding steps.", :yours, false, :person, true, true, [], "Shifts"),
    Group.new("courses", "Courses", "Registrations, cancellations and session reminders.", :yours, false, :person, true, true, [], "Courses"),
    Group.new("ticketing_sales", "Sales as they happen", "Each online sale, door sale, comp and pass.", :ticketing, true, :plan, false, true, [], "Ticketing"),
    Group.new("ticketing_reports", "Reports", "Daily summary, show day, after the show.", :ticketing, false, :plan, false, true, [], "Ticketing"),
    Group.new("ticketing_milestones", "Milestones", "Sales opened, almost sold out, sold out.", :ticketing, true, :plan, false, true, [], "Ticketing"),
    Group.new("ticketing_money", "Money", "Refunds, disputes, withdrawals, canceled shows.", :ticketing, true, :plan, false, true, [], "Ticketing")
  ].freeze

  # The automated notices that became Notifications (V1.1 plan §9), by their
  # ContentTemplate key: MessageService.create_message turns a system message
  # with one of these keys into a Notification for each recipient. Every
  # email still goes; message-only notices reach email through the unread
  # digest, as they did. Areas that send Notifier.deliver or
  # ContentTemplateService.deliver(notification:) themselves aren't listed.
  TEMPLATES = {
    # Casting and vacancies
    "casting_table_notification" => "casting", "show_canceled" => "casting",
    "vacancy_created" => "casting", "vacancy_filled" => "casting", "vacancy_reclaimed" => "casting",
    "vacancy_invitation" => "casting", "request_agreement_signature" => "casting",
    "talent_left_production" => "casting",
    # Sign-ups and auditions
    "sign_up_confirmation" => "signups", "sign_up_queued" => "signups", "sign_up_slot_assigned" => "signups",
    "sign_up_slot_changed" => "signups", "sign_up_cancelled" => "signups",
    "sign_up_registration_notification" => "signups", "audition_request_submitted" => "signups",
    # Courses
    "course_registration_confirmed" => "courses", "course_registration_producer_notification" => "courses",
    "course_cancelled_registrant" => "courses",
    # Shifts and hours
    "shift_declined_manager" => "shifts",
    # Pay and Contracts, from senders that still go through messages
    "staff_1099_ready" => "pay", "contract_person_added" => "contracts",
    # Ticketing: the Tap to Pay launch (TapToPayLaunch), to everyone who can sell at a door that has it
    "tap_to_pay_launch_message" => "ticketing_milestones"
  }.freeze
  # Notices a manager can write or edit before sending (V1.1 plan §9,
  # option 3, Tim 2026-10-20): always a Notification, and also a Message
  # from the manager when they changed the words or added a note
  # (ManagerWords; the sender passes custom_words:). One push, one email.
  VOICED = {
    "cast_notification" => "casting", "removed_from_cast_notification" => "casting",
    "audition_added_to_cast" => "signups", "audition_not_cast" => "signups",
    "audition_invitation" => "signups", "audition_not_invited" => "signups",
    "staff_schedule_notification" => "shifts", "staff_onboarding_invite" => "shifts",
    "staff_availability_confirm_request" => "shifts",
    "staff_w9_request" => "pay", "staff_w9_reminder" => "pay",
    "payout_setup_reminder" => "pay", "payment_setup_reminder" => "pay",
    "group_member_added" => "invitations", "questionnaire_invitation" => "invitations",
    "contract_invoice" => "contracts", "contract_invoice_reminder" => "contracts"
  }.freeze

  # TicketingNotifications::KINDS' groups, to these.
  TICKETING = {
    "Sales as they happen" => "ticketing_sales",
    "Reports" => "ticketing_reports",
    "Milestones" => "ticketing_milestones",
    "Money" => "ticketing_money"
  }.freeze

  module_function

  def keys = ALL.map(&:key)

  def find(key) = ALL.find { |g| g.key == key.to_s } || raise(ArgumentError, "No notification group #{key}")

  def for_ticketing_kind(kind_key)
    kind = TicketingNotifications::KINDS.find { |k| k.key == kind_key.to_s } || raise(ArgumentError, "No ticketing kind #{kind_key}")
    find(TICKETING.fetch(kind.group))
  end

  def category_for_template(template_key) = TEMPLATES[template_key.to_s]

  def voiced_category(template_key) = VOICED[template_key.to_s]

  # The list's filters: the areas that have something in them.
  def areas = ALL.select(&:live).map(&:area).compact.uniq
end

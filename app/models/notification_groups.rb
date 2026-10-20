# frozen_string_literal: true

# The few groups a person sets Push and Email for (Account settings →
# Notifications). The Notifications list always shows everything.
#
# live: whether anything sends into the group yet. Areas move off automated
# Messages one at a time (V1.1 plan §9); a group's Push switch only shows once
# its area has moved, so no switch promises what nothing does.
# email: :person (the person's own switch), :plan (the organization picks, by
# plan: Ticketing settings → Notifications, Tim 2026-10-20) or nil (no email).
# legacy_email: the older preference keys this group's Email switch stands
# for, so emails that read them keep honoring the person's choice.
module NotificationGroups
  Group = Data.define(:key, :label, :description, :section, :push_default, :email, :email_default, :live, :legacy_email, :area) do
    def email_by_plan? = email == :plan
    def ticketing? = section == :ticketing
  end

  ALL = [
    Group.new("casting", "Casting and vacancies", "You're cast, a show changes, someone needs cover.", :yours, true, :person, true, false, %w[vacancy_invitations vacancy_notifications], "Casting"),
    Group.new("signups", "Sign-ups and auditions", "Spots, results, invitations to audition, reminders before a deadline.", :yours, true, :person, true, false, %w[audition_invitations], "Sign-ups"),
    Group.new("invitations", "Invitations", "To join a group or a production team.", :yours, true, :person, true, false, %w[group_invitations], nil),
    Group.new("pay", "Your pay", "Pay on its way, deposited or returned; bank setup and tax forms.", :yours, true, :person, true, false, [], "Pay"),
    Group.new("contracts", "Contracts", "Signed, countersigned, amended, and reminders to sign.", :yours, true, :person, true, false, [], "Contracts"),
    Group.new("shifts", "Shifts and hours", "Shifts assigned, hours approved, onboarding steps.", :yours, false, :person, true, false, [], "Shifts"),
    Group.new("courses", "Courses", "Registrations, cancellations and session reminders.", :yours, false, :person, true, false, [], "Courses"),
    Group.new("ticketing_sales", "Sales as they happen", "Each online sale, door sale, comp and pass.", :ticketing, true, :plan, false, true, [], "Ticketing"),
    Group.new("ticketing_reports", "Reports", "Daily summary, show day, after the show.", :ticketing, false, :plan, false, true, [], "Ticketing"),
    Group.new("ticketing_milestones", "Milestones", "Sales opened, almost sold out, sold out.", :ticketing, true, :plan, false, true, [], "Ticketing"),
    Group.new("ticketing_money", "Money", "Refunds, disputes, withdrawals, canceled shows.", :ticketing, true, :plan, false, true, [], "Ticketing")
  ].freeze

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

  # The list's filters: the areas that have something in them.
  def areas = ALL.select(&:live).map(&:area).compact.uniq
end

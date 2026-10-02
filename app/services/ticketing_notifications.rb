# frozen_string_literal: true

# Who at a theater hears about what in Ticketing (Ticketing settings →
# Notifications): each kind of notice goes to the managers and extra email
# addresses the theater ticked. Until the theater saves its own choices, the
# defaults below apply to every manager.
class TicketingNotifications
  Kind = Data.define(:key, :group, :label, :description, :default_on)

  KINDS = [
    Kind.new("sale", "Sales", "Each sale", "Who bought, what, and how full the show is now. Can be a lot of email.", false),
    Kind.new("daily_summary", "Sales", "Daily summary", "Every morning: yesterday's sales and refunds, and how each upcoming show is selling.", true),
    Kind.new("show_day", "Sales", "Show day", "The morning of each show: tickets sold, comps, and the door list.", true),
    Kind.new("after_show", "Sales", "After the show", "The day after: who came, who didn't, and the money now available.", true),
    Kind.new("sold_out", "Milestones", "Sold out", "A show or a ticket type sells out.", true),
    Kind.new("almost_sold_out", "Milestones", "Almost sold out", "Ten percent of the seats left (or five, whichever is more).", true),
    Kind.new("sales_opened", "Milestones", "Sales opened", "A show you scheduled goes on sale.", false),
    Kind.new("refund_issued", "Money", "Refund given", "Who refunded what, so everyone on the team knows.", false),
    Kind.new("refund_problem", "Money", "Refund problem", "A refund didn't go through, or is waiting on money.", true),
    Kind.new("dispute", "Money", "Disputed charge", "A buyer asked their bank for their money back.", true),
    Kind.new("withdrawal", "Money", "Withdrawals", "Money sent to your bank, or a withdrawal that didn't go through.", true),
    Kind.new("cancellation_done", "Money", "Show cancellation done", "Every buyer of a canceled show has been refunded (or which ones couldn't be).", true)
  ].freeze

  KEYS = KINDS.map(&:key).freeze

  def initialize(organization)
    @organization = organization
    @profile = TicketingProfile.for(organization)
  end

  # Managers and the owner, the pool every notice picks from.
  def managers
    ids = @organization.organization_roles.where(company_role: "manager").pluck(:user_id)
    ids << @organization.owner_id if @organization.owner_id
    User.where(id: ids.uniq.compact).includes(:default_person).sort_by { |u| (u.person&.name || u.email_address).downcase }
  end

  def extra_emails
    Array(@profile.notification_emails).map(&:to_s).compact_blank
  end

  # Recipient keys ("user:12", "email:box@x.com") ticked for a kind.
  def ticked(kind_key)
    rules = @profile.notification_rules.presence
    return default_ticked(kind_key) unless rules

    Array(rules[kind_key])
  end

  def ticked?(kind_key, recipient_key)
    ticked(kind_key).include?(recipient_key)
  end

  # The email addresses a notice goes to right now: ticked managers still
  # managing, and ticked extra addresses still on the list.
  def emails_for(kind_key)
    keys = ticked(kind_key)
    manager_emails = managers.select { |u| keys.include?("user:#{u.id}") }.map(&:email_address)
    extras = extra_emails.select { |e| keys.include?("email:#{e}") }
    (manager_emails + extras).map(&:downcase).uniq
  end

  def save!(rules:, emails:)
    emails = Array(emails).map { |e| e.to_s.strip.downcase }.compact_blank.uniq
    bad = emails.reject { |e| e.match?(URI::MailTo::EMAIL_REGEXP) }
    raise ArgumentError, "#{bad.first} isn't an email address." if bad.any?

    allowed = managers.map { |u| "user:#{u.id}" } + emails.map { |e| "email:#{e}" }
    clean = KEYS.to_h { |key| [ key, Array(rules.to_h[key]).map(&:to_s) & allowed ] }
    @profile.update!(notification_emails: emails, notification_rules: clean)
  end

  private

  def default_ticked(kind_key)
    kind = KINDS.find { |k| k.key == kind_key }
    return [] unless kind&.default_on

    managers.map { |u| "user:#{u.id}" }
  end
end

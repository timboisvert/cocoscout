# frozen_string_literal: true

# Who at an organization hears about what in Ticketing (Ticketing settings →
# Notifications). Each person has a plan (Tim, 2026-10-20): Everything, The
# usual, Just the money, their own pick, or nothing. A plan takes in new
# kinds of email on its own, so adding one never means re-ticking anyone.
#
# Recipients are the organization's managers (listed on their own, on The
# usual until someone changes them) and any other address the organization
# adds, like a box office inbox (on nothing until it's given a plan).
# Stored on the profile as notification_plans:
#   { "user:12" => { "plan" => "usual" },
#     "email:box@x.com" => { "plan" => "custom", "kinds" => ["sale", "door_sale"] } }
class TicketingNotifications
  Kind = Data.define(:key, :group, :label, :description, :default_on)
  Plan = Data.define(:key, :label, :description)
  Recipient = Data.define(:key, :name, :email, :user, :plan, :kinds) do
    def address? = key.start_with?("email:")
  end

  KINDS = [
    # One row per way tickets go out (Tim, 2026-10-19): online, at the door,
    # comps, passes. Each has its own email (ticketing_<key>).
    Kind.new("sale", "Sales as they happen", "Each online sale", "Someone buys online or on your website: who, what, and how full the show is now.", false),
    Kind.new("door_sale", "Sales as they happen", "Each door sale", "Tap, scan to pay or cash at the door: who sold it, and how it was paid.", false),
    Kind.new("comp_issued", "Sales as they happen", "Each comp issued", "Comps from Ticketing, a production team or the door: who gave them, and to whom.", false),
    Kind.new("pass_redeemed", "Sales as they happen", "Each pass redeemed", "Someone uses a pass, online or at the door, and what's left on it.", false),
    Kind.new("daily_summary", "Reports", "Daily summary", "Every morning: yesterday's sales and refunds, and how each upcoming show is selling.", true),
    Kind.new("show_day", "Reports", "Show day", "The morning of each show: tickets sold, comps, and the door list.", true),
    Kind.new("after_show", "Reports", "After the show", "The day after: who came, who didn't, and the money now available.", true),
    Kind.new("sales_opened", "Milestones", "Sales opened", "A show you scheduled goes on sale.", false),
    Kind.new("almost_sold_out", "Milestones", "Almost sold out", "Ten percent of the seats left (or five, whichever is more).", true),
    Kind.new("sold_out", "Milestones", "Sold out", "A show or a ticket type sells out.", true),
    Kind.new("refund_issued", "Money", "Refund given", "Who refunded what, so everyone on the team knows.", false),
    Kind.new("refund_problem", "Money", "Refund problem", "A refund didn't go through, or is waiting on money.", true),
    Kind.new("dispute", "Money", "Disputed charge", "A buyer asked their bank for their money back.", true),
    Kind.new("withdrawal", "Money", "Withdrawals", "Money sent to your bank, or a withdrawal that didn't go through.", true),
    Kind.new("cancellation_done", "Money", "Show cancellation done", "Every buyer of a canceled show has been refunded (or which ones couldn't be).", true)
  ].freeze

  KEYS = KINDS.map(&:key).freeze
  USUAL = KINDS.select(&:default_on).map(&:key).freeze
  MONEY = KINDS.select { |k| k.group == "Money" }.map(&:key).freeze

  PLANS = [
    Plan.new("everything", "Everything", "Every Ticketing email, and any new kind as it's added."),
    Plan.new("usual", "The usual", "The daily summary, show reports, milestones and money problems. Managers start here."),
    Plan.new("money", "Just the money", "Refunds, refund problems, disputed charges, withdrawals and canceled shows."),
    Plan.new("custom", "Pick my own", "Choose each email. Nothing new arrives until it's switched on."),
    Plan.new("nothing", "Nothing", "No Ticketing email.")
  ].freeze
  PLAN_KEYS = PLANS.map(&:key).freeze

  def self.kinds_for(plan, custom = [])
    case plan
    when "everything" then KEYS
    when "usual" then USUAL
    when "money" then MONEY
    when "custom" then KEYS & Array(custom)
    else []
    end
  end

  # What a plan sends, for the page's Stimulus controller: { "usual" => [...] }.
  def self.plan_kinds
    PLAN_KEYS.excluding("custom").index_with { |plan| kinds_for(plan) }
  end

  def initialize(organization)
    @organization = organization
    @profile = TicketingProfile.for(organization)
  end

  # Managers and the owner, the people listed on their own.
  def managers
    ids = @organization.organization_roles.where(company_role: "manager").pluck(:user_id)
    ids << @organization.owner_id if @organization.owner_id
    User.where(id: ids.uniq.compact).includes(:default_person).sort_by { |u| (u.person&.name || u.email_address).downcase }
  end

  # Everyone who can get Ticketing email: managers first, then the other
  # addresses, each with their plan and what it sends.
  def recipients
    plans = stored_plans
    people = managers.map do |user|
      key = "user:#{user.id}"
      build(key, user.person&.name.presence || user.email_address, user.email_address, user, plans[key] || { "plan" => "usual" })
    end
    addresses = plans.keys.select { |k| k.start_with?("email:") }.sort.map do |key|
      email = key.delete_prefix("email:")
      build(key, email, email, nil, plans[key])
    end
    people + addresses
  end

  def recipient(key)
    recipients.find { |r| r.key == key }
  end

  # The email addresses a notice goes to right now.
  def emails_for(kind_key)
    recipients.select { |r| r.kinds.include?(kind_key) }.map { |r| r.email.downcase }.uniq
  end

  # Sets one person's or address's plan. key "user:12", "email:x" or "new"
  # (an address being added); email renames or names an address.
  def save_plan!(key, plan:, kinds: [], email: nil)
    raise ArgumentError, "Pick a plan." unless PLAN_KEYS.include?(plan)

    plans = stored_plans
    if key.start_with?("user:")
      raise ArgumentError, "Only your organization's managers are listed here." unless managers.any? { |u| "user:#{u.id}" == key }

      new_key = key
    else
      address = email.to_s.strip.downcase
      raise ArgumentError, "#{address.presence || 'That'} isn't an email address." unless address.match?(URI::MailTo::EMAIL_REGEXP)
      raise ArgumentError, "#{address} is one of your managers; they're listed already." if managers.any? { |u| u.email_address.downcase == address }

      new_key = "email:#{address}"
      raise ArgumentError, "#{address} is on the list already." if new_key != key && plans.key?(new_key)

      plans.delete(key)
    end

    chosen = self.class.kinds_for("custom", kinds)
    plan = "nothing" if plan == "custom" && chosen.empty?
    plans[new_key] = plan == "custom" ? { "plan" => plan, "kinds" => chosen } : { "plan" => plan }
    save!(plans)
    recipient(new_key)
  end

  def remove_address!(key)
    raise ArgumentError, "Managers stay on the list; give them Nothing instead." unless key.start_with?("email:")

    plans = stored_plans
    plans.delete(key)
    save!(plans)
  end

  private

  def stored_plans
    (@profile.notification_plans.presence || {}).to_h.transform_values(&:to_h)
  end

  def build(key, name, email, user, stored)
    plan = PLAN_KEYS.include?(stored["plan"]) ? stored["plan"] : "nothing"
    Recipient.new(key: key, name: name, email: email, user: user, plan: plan, kinds: self.class.kinds_for(plan, stored["kinds"]))
  end

  def save!(plans)
    addresses = plans.keys.select { |k| k.start_with?("email:") }.map { |k| k.delete_prefix("email:") }.sort
    @profile.update!(notification_plans: plans, notification_emails: addresses)
  end
end

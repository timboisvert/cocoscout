# frozen_string_literal: true

class Organization < ApplicationRecord
  include PayoutScheduling
  # Payee-side Stripe Connect state, so an org can receive its own money (leftover
  # course revenue CocoScout holds) to its bank — same rail as Person/Contractor.
  include StripeConnectable

  belongs_to :owner, class_name: "User"
  belongs_to :organization_talent_pool, class_name: "TalentPool", optional: true
  has_many :productions, dependent: :destroy
  has_many :contracts, dependent: :destroy
  has_many :contractors, dependent: :destroy
  has_many :contract_service_options, dependent: :destroy
  has_many :payout_schemes, dependent: :destroy
  has_many :team_invitations, dependent: :destroy
  has_many :organization_roles, dependent: :destroy
  has_many :users, through: :organization_roles
  has_many :locations, dependent: :destroy
  has_many :casting_tables, dependent: :destroy
  # Staffing module
  has_many :house_roles, dependent: :destroy
  has_many :departments, dependent: :destroy
  has_many :staff_activations, dependent: :destroy
  has_many :performer_activations, dependent: :destroy
  has_many :staff_time_entries, dependent: :destroy
  has_many :organization_staff_members, dependent: :destroy
  has_many :shifts, dependent: :destroy
  has_many :staffing_finalizations, dependent: :destroy
  has_many :staff_schedule_removals, dependent: :destroy
  has_many :agreement_templates, dependent: :destroy
  has_many :contract_templates, dependent: :destroy
  has_many :questionnaires, dependent: :destroy
  has_many :org_payouts, dependent: :destroy
  has_many :payout_ledger_entries, dependent: :destroy
  has_many :payout_batches, dependent: :destroy
  has_and_belongs_to_many :people
  has_and_belongs_to_many :groups

  has_one_attached :logo

  # Talent pool mode determines how talent pools are organized
  # per_production: Each production has its own talent pool (can share between specific productions)
  # single: One unified talent pool across all productions
  enum :talent_pool_mode, {
    per_production: "per_production",
    single: "single"
  }, default: :per_production, prefix: :talent_pool

  scope :demo, -> { where(is_demo: true) }
  scope :non_demo, -> { where(is_demo: false) }

  # Subscription tiers. "free" is the Producer plan (default, for solo producers
  # and small teams); "paid" is the Pro plan. See #on_paid_plan?
  # for the access gate.
  enum :subscription_tier, { free: "free", paid: "paid" }, default: :free, prefix: :tier

  # Customer-facing plan names.
  TIER_NAMES = { "free" => "Producer", "paid" => "Pro" }.freeze

  # Modules that require the Pro tier. Everything else (Shows,
  # Casting, Auditions, Availability, basic Sign-ups, Messages, Contacts,
  # Documents, and Courses) is included on the Producer plan.
  PAID_FEATURES = %i[money contracts staffing casting_table reports agreements].freeze

  # Producer plan may schedule at most this many (non-canceled) shows/events per
  # calendar month, counting every event type including rehearsals.
  FREE_MONTHLY_EVENT_LIMIT = 6

  # Producer plan may run at most this many active, schedulable productions
  # (courses don't count — they're free with a per-transaction fee).
  FREE_PRODUCTION_LIMIT = 1

  validates :name, presence: true

  # The org's default answer to "how may a contractor pay us?" Online (the
  # Stripe pay link) is always available; this is the offline methods the org
  # normally accepts on top of it. Each contract inherits and can override.
  def default_contract_payment_methods
    ([ "online" ] + (Array(self[:default_contract_payment_methods]) & Contract::OFFLINE_PAYMENT_METHODS)).uniq
  end

  def default_offline_payment_methods
    default_contract_payment_methods - [ "online" ]
  end

  before_create :generate_invite_token

  # Generate or ensure invite token exists
  def ensure_invite_token!
    if invite_token.blank?
      generate_invite_token
      save!
    end
    invite_token
  end

  # Check if a user is the owner
  def owned_by?(user)
    owner_id == user&.id
  end

  # Contact email for Stripe Connect onboarding prefill (the owner's login email).
  def email
    owner&.email_address
  end

  # Get the user's role in this organization
  def role_for(user)
    return "owner" if owned_by?(user)

    organization_roles.find_by(user: user)&.company_role || "member"
  end

  # Check if user can manage this organization
  def manageable_by?(user)
    owned_by?(user) || organization_roles.exists?(user: user, company_role: "manager")
  end

  # ---- Subscription / entitlements ------------------------------------------

  # Single source of truth for Pro access. True when comped (indefinitely or
  # within a comp window) or holding an access-granting Stripe subscription.
  # past_due still grants access so a failed renewal doesn't lock people out
  # instantly (surfaced as a warning banner instead).
  def on_paid_plan?
    return true if comped_indefinitely?
    return true if comped_until.present? && comped_until.future?

    subscription_status.in?(%w[active trialing past_due])
  end

  # True when the org's Pro access comes from a comp rather than a paid Stripe subscription.
  def comped?
    comped_indefinitely? || (comped_until.present? && comped_until.future?)
  end

  # Customer-facing plan name reflecting effective access ("Pro"
  # when on the paid plan by any means, else "Producer").
  def plan_name
    on_paid_plan? ? TIER_NAMES["paid"] : TIER_NAMES["free"]
  end

  # Whether a given feature (symbol from PAID_FEATURES, or any free feature) is
  # available to this org. Free features and courses are always available.
  def feature_available?(feature)
    return true unless feature.to_sym.in?(PAID_FEATURES)

    on_paid_plan?
  end

  # Non-canceled shows/events for the calendar month containing +date+.
  def events_in_month(date = Time.current)
    Show.where(production: productions)
        .where(date_and_time: date.beginning_of_month..date.end_of_month)
        .where(canceled: false)
  end

  # True when a free org has already used its monthly event allowance for the
  # calendar month containing +date+. Paid orgs are never at the limit.
  def at_event_limit?(date = Time.current)
    return false if on_paid_plan?

    events_in_month(date).count >= FREE_MONTHLY_EVENT_LIMIT
  end

  # === Payout balances (derived from the ledger; never cached) ===

  # What this organization currently owes +payee+ (a Person/Contractor/Group),
  # in cents. Positive means we owe them; zero/negative means settled.
  def payout_balance_cents_for(payee, category: nil)
    payout_ledger_entries.for_payee(payee).for_category(category).sum(:amount_cents)
  end

  # Every payee this org has a non-zero balance with, as a Hash keyed by
  # [payee_type, payee_id] => balance_cents. One grouped query, no N+1.
  def payout_balances_by_payee
    payout_ledger_entries
      .group(:payee_type, :payee_id)
      .sum(:amount_cents)
      .reject { |_key, cents| cents.zero? }
  end

  # Active, schedulable productions that count toward the Producer plan limit
  # (courses and archived productions are excluded).
  def productions_counting_toward_limit
    productions.active.schedulable
  end

  # True when a Producer-plan org has reached its production allowance. Paid
  # orgs run unlimited productions.
  def at_production_limit?
    return false if on_paid_plan?

    productions_counting_toward_limit.count >= FREE_PRODUCTION_LIMIT
  end

  # Organization stats
  def active_productions_count
    # A production is active if it has shows scheduled in the future
    productions.joins(:shows).where("shows.date_and_time >= ? AND shows.canceled = ?", Time.current,
                                    false).distinct.count
  end

  def team_size
    users.count
  end

  def member_count
    people.count
  end

  # Cached directory counts for display in headers/pagination
  def cached_directory_counts
    Rails.cache.fetch([ "org_directory_counts_v1", id, people.maximum(:updated_at), groups.maximum(:updated_at) ],
                      expires_in: 10.minutes) do
      {
        people: people.count,
        groups: groups.count
      }
    end
  end

  # Returns the org-level talent pool (creates if needed when switching to single mode)
  def talent_pool
    organization_talent_pool
  end

  # Create or get the organization-level talent pool
  def find_or_create_talent_pool!
    return organization_talent_pool if organization_talent_pool.present?

    # Create a new talent pool that belongs to the first production
    # (TalentPool requires a production, so we use the first one as the "owner")
    first_production = productions.type_in_house.order(:created_at).first
    return nil unless first_production

    pool = TalentPool.create!(
      production: first_production,
      name: "#{name} Talent Pool"
    )
    update!(organization_talent_pool: pool)
    pool
  end

  # Get all members across all production talent pools (for merge preview)
  def all_talent_pool_members
    person_ids = Set.new
    group_ids = Set.new

    productions.type_in_house.each do |prod|
      pool = prod.talent_pool
      person_ids.merge(pool.people.pluck(:id))
      group_ids.merge(pool.groups.pluck(:id))
    end

    {
      people: Person.where(id: person_ids.to_a),
      groups: Group.where(id: group_ids.to_a),
      people_count: person_ids.size,
      groups_count: group_ids.size
    }
  end

  private

  def generate_invite_token
    self.invite_token = SecureRandom.urlsafe_base64(16)
  end
end

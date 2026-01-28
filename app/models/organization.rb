# frozen_string_literal: true

class Organization < ApplicationRecord
  belongs_to :owner, class_name: "User"
  belongs_to :organization_talent_pool, class_name: "TalentPool", optional: true
  has_many :productions, dependent: :destroy
  has_many :contracts, dependent: :destroy
  has_many :payout_schemes, dependent: :destroy
  has_many :ticket_fee_templates, dependent: :destroy
  has_many :ticketing_providers, dependent: :destroy
  has_many :team_invitations, dependent: :destroy
  has_many :organization_roles, dependent: :destroy
  has_many :users, through: :organization_roles
  has_many :locations, dependent: :destroy
  has_many :casting_tables, dependent: :destroy
  has_many :payroll_runs, dependent: :destroy
  has_one :payroll_schedule, dependent: :destroy
  has_and_belongs_to_many :people
  has_and_belongs_to_many :groups

  has_one_attached :logo

  # Forum mode determines how message boards are organized
  # per_production: Each production has its own separate forum
  # shared: All productions in this org share one forum
  enum :forum_mode, {
    per_production: "per_production",
    shared: "shared"
  }, default: :per_production, prefix: :forum

  # Talent pool mode determines how talent pools are organized
  # per_production: Each production has its own talent pool (can share between specific productions)
  # single: One unified talent pool across all productions
  enum :talent_pool_mode, {
    per_production: "per_production",
    single: "single"
  }, default: :per_production, prefix: :talent_pool

  validates :name, presence: true

  before_create :generate_invite_token

  # Get the display name for the shared forum
  def forum_display_name
    shared_forum_name.presence || name
  end

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

  # Get the user's role in this organization
  def role_for(user)
    return "owner" if owned_by?(user)

    organization_roles.find_by(user: user)&.company_role || "member"
  end

  # Check if user can manage this organization
  def manageable_by?(user)
    owned_by?(user) || organization_roles.exists?(user: user, company_role: "manager")
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

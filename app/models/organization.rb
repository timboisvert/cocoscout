# frozen_string_literal: true

class Organization < ApplicationRecord
  belongs_to :owner, class_name: "User"
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

  private

  def generate_invite_token
    self.invite_token = SecureRandom.urlsafe_base64(16)
  end
end

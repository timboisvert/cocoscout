class Organization < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :productions, dependent: :destroy
  has_many :team_invitations, dependent: :destroy
  has_many :organization_roles, dependent: :destroy
  has_many :users, through: :organization_roles
  has_many :locations, dependent: :destroy
  has_and_belongs_to_many :people

  has_one_attached :logo

  validates :name, presence: true

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
    productions.joins(:shows).where("shows.date_and_time >= ? AND shows.canceled = ?", Time.current, false).distinct.count
  end

  def team_size
    users.count
  end

  def member_count
    people.count
  end
end

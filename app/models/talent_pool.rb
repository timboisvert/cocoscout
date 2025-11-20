class TalentPool < ApplicationRecord
  belongs_to :production
  has_many :talent_pool_memberships, dependent: :destroy
  has_many :people, through: :talent_pool_memberships, source: :member, source_type: "Person"
  has_many :groups, through: :talent_pool_memberships, source: :member, source_type: "Group"
  # Note: cast_assignment_stages are deleted via Production's before_destroy callback
  # to avoid foreign key constraint issues
  has_many :cast_assignment_stages

  validates :name, presence: true

  # Helper method to get all members (both people and groups)
  def members
    talent_pool_memberships.includes(:member).map(&:member)
  end
end

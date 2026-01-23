# frozen_string_literal: true

class TalentPool < ApplicationRecord
  belongs_to :production
  has_many :talent_pool_memberships, dependent: :destroy
  has_many :talent_pool_shares, dependent: :destroy
  has_many :shared_productions, through: :talent_pool_shares, source: :production
  has_many :people, through: :talent_pool_memberships, source: :member, source_type: "Person"
  has_many :groups, through: :talent_pool_memberships, source: :member, source_type: "Group"
  # NOTE: cast_assignment_stages are deleted via Production's before_destroy callback
  # to avoid foreign key constraint issues
  has_many :cast_assignment_stages

  validates :name, presence: true

  # All productions that use this pool (owner + shared)
  def all_productions
    Production.where(id: [ production_id ] + shared_productions.pluck(:id))
  end

  # Display name showing all production names (for dropdowns)
  def production_names
    names = [ production.name ]
    names += shared_productions.pluck(:name)
    names.join(", ")
  end

  # Helper method to get all members (both people and groups)
  def members
    talent_pool_memberships.includes(:member).map(&:member)
  end

  # Cached member counts for display in lists
  def cached_member_counts
    Rails.cache.fetch([ "talent_pool_counts_v1", id, talent_pool_memberships.maximum(:updated_at) ],
                      expires_in: 10.minutes) do
      {
        people: talent_pool_memberships.where(member_type: "Person").count,
        groups: talent_pool_memberships.where(member_type: "Group").count,
        total: talent_pool_memberships.count
      }
    end
  end
end

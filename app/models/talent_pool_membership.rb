# frozen_string_literal: true

class TalentPoolMembership < ApplicationRecord
  belongs_to :talent_pool, touch: true
  belongs_to :member, polymorphic: true

  validates :talent_pool, presence: true
  validates :member, presence: true
  validates :member_id, uniqueness: { scope: %i[talent_pool_id member_type] }

  # A person/group in a talent pool must belong to that pool's organization.
  # Enforcing it here guarantees the invariant no matter which path adds the
  # membership (auditions, course registration, invites, imports, future code),
  # so we never again strand a pool member with no org link.
  after_create :ensure_member_in_organization

  private

  def ensure_member_in_organization
    org = talent_pool&.production&.organization
    return unless org

    case member
    when Person
      org.people << member unless org.people.exists?(member.id)
    when Group
      org.groups << member unless org.groups.exists?(member.id)
    end
  end
end

# frozen_string_literal: true

# A follower on a list.
class MailingListMembership < ApplicationRecord
  belongs_to :mailing_list
  belongs_to :follower

  validates :follower_id, uniqueness: { scope: :mailing_list_id }
  validate :same_organization

  # Someone joined a list that is shared through a contract: the Pro
  # organizations it's shared with get them too (SharedFollowers).
  after_create_commit { SharedFollowersSyncJob.perform_later(mailing_list_id) if mailing_list&.shared? }

  private

  def same_organization
    return if mailing_list.nil? || follower.nil?

    errors.add(:follower, "isn't this organization's") unless follower.organization_id == mailing_list.organization_id
  end
end

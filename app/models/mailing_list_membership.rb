# frozen_string_literal: true

# A follower on a list.
class MailingListMembership < ApplicationRecord
  belongs_to :mailing_list
  belongs_to :follower

  validates :follower_id, uniqueness: { scope: :mailing_list_id }
  validate :same_organization

  private

  def same_organization
    return if mailing_list.nil? || follower.nil?

    errors.add(:follower, "isn't this organization's") unless follower.organization_id == mailing_list.organization_id
  end
end

# frozen_string_literal: true

# A production a mailing list collects from: its checkout offers the list's box.
class MailingListProduction < ApplicationRecord
  belongs_to :mailing_list
  belongs_to :production

  validates :production_id, uniqueness: { scope: :mailing_list_id }
  validate :same_organization

  private

  def same_organization
    return if mailing_list.nil? || production.nil?

    errors.add(:production, "isn't this organization's") unless production.organization_id == mailing_list.organization_id
  end
end

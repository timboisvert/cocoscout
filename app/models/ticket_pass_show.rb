# frozen_string_literal: true

# One show in a dated pass: the date (a listing) and which of its ticket
# types a pass holder gets a seat in. A custom split also types its share.
class TicketPassShow < ApplicationRecord
  belongs_to :ticket_pass, inverse_of: :pass_shows
  belongs_to :ticket_listing
  belongs_to :ticket_tier

  validates :share_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :ticket_listing_id, uniqueness: { scope: :ticket_pass_id, message: "is already in this pass" }
  validate :tier_is_this_shows_own_plain_type
  validate :same_organization

  before_validation { self.ticket_listing ||= ticket_tier&.ticket_listing }

  private

  def tier_is_this_shows_own_plain_type
    return if ticket_tier.nil?

    errors.add(:ticket_tier, "must be one of this show's ticket types") unless ticket_tier.ticket_listing_id == ticket_listing_id
    errors.add(:ticket_tier, "can't be a bundle") if ticket_tier.bundle?
  end

  def same_organization
    return if ticket_listing.nil? || ticket_pass.nil?

    errors.add(:ticket_listing, "must be one of your organization's shows") unless ticket_listing.organization_id == ticket_pass.organization_id
  end
end

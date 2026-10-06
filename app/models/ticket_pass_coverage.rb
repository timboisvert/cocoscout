# frozen_string_literal: true

# A production a credit pass covers: any of its dates, in the ticket type
# named (or its first plain one).
class TicketPassCoverage < ApplicationRecord
  belongs_to :ticket_pass, inverse_of: :coverages
  belongs_to :production

  validates :production_id, uniqueness: { scope: :ticket_pass_id, message: "is already covered" }
  validate :same_organization

  # The ticket type a credit gives at this date.
  def tier_at(listing)
    tiers = listing.ticket_tiers.select { |tier| tier.archived_at.nil? && !tier.bundle? && !tier.hidden? }
    tiers.find { |tier| tier_name.present? && tier.name.casecmp?(tier_name.strip) } || tiers.min_by(&:position)
  end

  private

  def same_organization
    return if production.nil? || ticket_pass.nil?

    errors.add(:production, "must be one of your productions") unless production.organization_id == ticket_pass.organization_id
  end
end

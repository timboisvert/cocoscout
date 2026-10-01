# frozen_string_literal: true

# Which taxes apply to a kind of money (tickets, courses), and where. The
# org's default rule has no scope; a rule scoped to a venue, production,
# listing or tier overrides it there — the most specific one wins (see
# TaxCalculator). A rule either names its rates (they add up) or says the
# sale is exempt, with the reason tax returns ask for.
class TaxRule < ApplicationRecord
  MONEY_KINDS = %w[tickets courses].freeze
  MODES = %w[added included].freeze
  SCOPE_TYPES = %w[Location Production TicketListing TicketTier].freeze

  belongs_to :organization
  # Where it applies (columns scope_type/scope_id): nil = the org's default.
  belongs_to :applies_to, polymorphic: true, optional: true, foreign_type: :scope_type, foreign_key: :scope_id

  validates :money_kind, inclusion: { in: MONEY_KINDS }
  validates :mode, inclusion: { in: MODES }
  validates :scope_type, inclusion: { in: SCOPE_TYPES }, allow_nil: true
  validates :exemption_reason, presence: true, if: :exempt?
  validate :rates_belong_to_organization

  def tax_rates
    TaxRate.where(organization_id: organization_id, id: Array(tax_rate_ids).map(&:to_i))
  end

  def included?
    mode == "included"
  end

  private

  def rates_belong_to_organization
    ids = Array(tax_rate_ids).map(&:to_i)
    return if ids.empty?

    errors.add(:tax_rate_ids, "must be this organization's rates") if tax_rates.count != ids.uniq.size
  end
end

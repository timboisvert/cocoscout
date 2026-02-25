# frozen_string_literal: true

# Join table that declares a payout scheme as the default for a production
# (or org-wide if production_id is nil) starting from an optional effective_from date.
#
# Multiple defaults can coexist with different effective_from dates.
# When resolving which scheme to use, pick the one with the latest effective_from <= show date.
class PayoutSchemeDefault < ApplicationRecord
  belongs_to :payout_scheme
  belongs_to :production, optional: true

  validates :payout_scheme_id, presence: true

  # Ensure only one default per production per effective_from date
  validates :effective_from, uniqueness: {
    scope: :production_id,
    message: "already has a default scheme for this date"
  }, if: -> { production_id.present? }

  # For org-level defaults (production_id nil): ensure uniqueness per org + effective_from
  validate :unique_org_level_default, if: -> { production_id.blank? }

  scope :for_production, ->(production) { where(production: production) }
  scope :org_level, -> { where(production_id: nil) }
  scope :effective_on, ->(date) { where("effective_from IS NULL OR effective_from <= ?", date) }
  scope :by_effective_date_desc, -> {
    order(Arel.sql("CASE WHEN effective_from IS NULL THEN 0 ELSE 1 END DESC, effective_from DESC"))
  }

  private

  def unique_org_level_default
    org_id = payout_scheme&.organization_id
    return unless org_id

    existing = PayoutSchemeDefault.joins(:payout_scheme)
      .where(production_id: nil, effective_from: effective_from)
      .where(payout_schemes: { organization_id: org_id })
      .where.not(id: id)

    if existing.exists?
      errors.add(:effective_from, "already has an organization-level default for this date")
    end
  end
end

# frozen_string_literal: true

# Says a production pays its performers with a payout calculation
# (PayoutScheme), from an optional effective_from date. A production can have
# several rows with different dates ("starting on…"); resolving a show picks
# the latest effective_from on or before the show's date (nil = always).
#
# There is no organization-level default: a production without a row has no
# calculation, and its shows can't be worked out until someone chooses one.
class PayoutSchemeDefault < ApplicationRecord
  belongs_to :payout_scheme
  belongs_to :production

  validates :payout_scheme_id, presence: true

  # One row per production per start date.
  validates :effective_from, uniqueness: {
    scope: :production_id,
    message: "already has a calculation starting on this date"
  }

  scope :for_production, ->(production) { where(production: production) }
  scope :effective_on, ->(date) { where("payout_scheme_defaults.effective_from IS NULL OR payout_scheme_defaults.effective_from <= ?", date) }
  scope :by_effective_date_desc, -> {
    order(Arel.sql("CASE WHEN payout_scheme_defaults.effective_from IS NULL THEN 0 ELSE 1 END DESC, payout_scheme_defaults.effective_from DESC"))
  }

  # The row in effect on a date out of an already-loaded set (one production's
  # rows) — the same pick as effective_on + by_effective_date_desc, in Ruby.
  def self.in_effect_on(rows, on)
    rows.select { |row| row.effective_from.nil? || row.effective_from <= on }
        .max_by { |row| row.effective_from ? [ 1, row.effective_from ] : [ 0, Date.new(1) ] }
  end
end

# frozen_string_literal: true

# The permanent record of one tax on one taxed thing (a ticket, later a course
# registration): which rate, what it was charged on, and how much — or that it
# was exempt, and why. A refund adds a negative line pointing at the original
# rather than changing it. The theater's "Taxes collected" report reads
# straight from these.
class TaxLine < ApplicationRecord
  belongs_to :organization
  belongs_to :taxable, polymorphic: true
  belongs_to :tax_rate, optional: true
  belongs_to :reversal_of, class_name: "TaxLine", optional: true

  validates :name, :sale_date, presence: true
  validates :base_cents, :tax_cents, :rate_bps, numericality: { only_integer: true }

  scope :exempt, -> { where(exempt: true) }
  scope :taxed, -> { where(exempt: false) }
end

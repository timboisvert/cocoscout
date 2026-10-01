# frozen_string_literal: true

# A tax the theater collects — "Sales tax 10.25%", "Chicago amusement tax 9%".
# The theater is the seller and remits it; CocoScout collects it on their
# behalf and hands it over with their money. A rate that has been used is
# never edited: changing it retires this one and starts a new one, so every
# past sale still shows the rate it was charged at.
class TaxRate < ApplicationRecord
  KINDS = %w[sales amusement other].freeze
  REMITTERS = %w[organization].freeze

  belongs_to :organization
  has_many :tax_lines, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 80 }
  validates :rate_bps, numericality: { only_integer: true, in: 0..10_000 }
  validates :kind, inclusion: { in: KINDS }
  validates :remitter, inclusion: { in: REMITTERS }

  scope :current, -> { where(archived_at: nil) }

  def percent
    rate_bps / 100.0
  end

  # "10.25%"
  def percent_label
    "#{format('%g', percent)}%"
  end

  def label
    receipt_label.presence || name
  end

  def used?
    tax_lines.exists?
  end
end

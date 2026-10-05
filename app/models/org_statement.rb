# frozen_string_literal: true

# A theater's statement for one month (see OrgStatementBuilder for what's in
# it). The PDF is attached; the email goes to the owner once.
class OrgStatement < ApplicationRecord
  belongs_to :organization
  has_one_attached :pdf

  validates :month, presence: true, uniqueness: { scope: :organization_id }

  scope :newest_first, -> { order(month: :desc) }

  def label
    month.strftime("%B %Y")
  end

  def total_paid_cents
    totals["total_paid_cents"].to_i
  end

  def filename
    "CocoScout statement #{organization.name.parameterize} #{month.strftime('%Y-%m')}.pdf"
  end
end

# frozen_string_literal: true

# The org's payer details: who issues the 1099s its contractors receive. One
# row per organization, created the first time someone saves Staffing →
# Settings → Taxes. The EIN is encrypted; screens only ever show its last four.
class OrganizationTaxSetting < ApplicationRecord
  belongs_to :organization

  encrypts :ein

  before_validation :normalize_ein

  validates :organization_id, uniqueness: true
  validates :ein, format: { with: /\A\d{9}\z/, message: "must be 9 digits" }, allow_blank: true
  validates :state, format: { with: /\A[A-Z]{2}\z/, message: "must be a two-letter state code" }, allow_blank: true
  validates :zip, format: { with: /\A\d{5}(-\d{4})?\z/, message: "must be a ZIP code" }, allow_blank: true

  # Everything a 1099 needs from the payer is filled in.
  def complete?
    [ legal_name, ein, address_line1, city, state, zip ].all?(&:present?)
  end

  def masked_ein
    ein_last4.present? ? "••-•••#{ein_last4}" : nil
  end

  private

  def normalize_ein
    return if ein.nil?

    digits = ein.to_s.gsub(/\D/, "")
    self.ein = digits.presence
    self.ein_last4 = digits.last(4).presence
  end
end

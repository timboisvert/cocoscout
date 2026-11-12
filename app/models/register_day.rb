# frozen_string_literal: true

# One location's business day on a register (Square): sales by our
# category, tips, sales tax, refunds, the register's fees, and the net on
# its way to the bank. Read by the day's Settle up worksheet; nothing here
# reaches the books until the day is settled.
class RegisterDay < ApplicationRecord
  belongs_to :integration
  belongs_to :organization
  belongs_to :location, optional: true

  scope :on, ->(date) { where(business_date: date) }
  scope :counted, -> { joins(:integration).where(integrations: { status: %w[connected error] }) }

  def sales_cents = sales_by_category.values.sum(&:to_i)

  # Sales after refunds, by category, in our words.
  def category_rows
    sales_by_category.sort_by { |_, cents| -cents.to_i }.map { |key, cents| [ Integration::REGISTER_CATEGORIES.fetch(key, "Other"), cents.to_i ] }
  end

  def location_name
    location&.name || integration.external_locations.find { |l| l["id"] == external_location_id }&.dig("name") || "Register"
  end

  def any? = orders_count.positive? || sales_cents.positive? || refunds_cents.positive?
end

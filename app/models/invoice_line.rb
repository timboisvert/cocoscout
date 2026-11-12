# frozen_string_literal: true

# One line of an invoice: what, how many, at what each.
class InvoiceLine < ApplicationRecord
  belongs_to :invoice, inverse_of: :invoice_lines

  validates :description, presence: true
  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :compute_amount

  def compute_amount
    self.amount_cents = (quantity.to_d * unit_cents.to_i).round
  end

  def unit = unit_cents / 100.0

  def unit=(value)
    self.unit_cents = (value.to_s.delete(",$ ").to_d * 100).round
  end

  def quantity_label
    quantity == quantity.to_i ? quantity.to_i.to_s : quantity.to_s
  end
end

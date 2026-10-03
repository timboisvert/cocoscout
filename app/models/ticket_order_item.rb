# frozen_string_literal: true

# One product line on a ticket order: "2 × Champagne bottle at $45", the tax
# on it, and whether it's been handed over at the door. Name, description,
# price and the revenue rule are copied from the offer when the order is
# made, so later changes to the product never rewrite a sale.
#
# "reserved" while its order is waiting to be paid (it holds nothing; products
# have no stock), "valid" once paid, then refunded or void.
class TicketOrderItem < ApplicationRecord
  STATUSES = %w[reserved valid refunded void exchanged].freeze
  SOLD_STATUSES = %w[valid].freeze

  belongs_to :ticket_order
  belongs_to :organization
  belongs_to :ticket_listing
  belongs_to :ticket_product
  belongs_to :fulfilled_by, class_name: "User", optional: true

  has_many :tax_lines, as: :taxable, dependent: :delete_all

  validates :status, inclusion: { in: STATUSES }
  validates :name, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :unit_price_cents, :tax_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :fulfilled_quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :sold, -> { where(status: SOLD_STATUSES) }

  def price_cents
    unit_price_cents * quantity
  end

  def sold?
    SOLD_STATUSES.include?(status)
  end

  def fulfilled?
    fulfilled_quantity >= quantity
  end

  def label
    "#{quantity} × #{name}"
  end
end

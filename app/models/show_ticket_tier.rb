# frozen_string_literal: true

class ShowTicketTier < ApplicationRecord
  belongs_to :show_ticketing
  belongs_to :ticket_tier, optional: true # Link to template tier

  has_many :ticket_offers, dependent: :restrict_with_error
  has_many :ticket_sales, dependent: :restrict_with_error
  has_many :ticket_bundle_items, dependent: :destroy

  validates :name, presence: true
  validates :capacity, presence: true, numericality: { greater_than: 0 }
  validates :available, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :sold, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :held, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :position, presence: true, numericality: { greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(:position) }
  scope :with_availability, -> { where("available > 0") }

  before_validation :ensure_defaults

  def default_price
    default_price_cents / 100.0
  end

  def default_price=(value)
    self.default_price_cents = (value.to_f * 100).round
  end

  # Record a sale (decrease available, increase sold)
  def record_sale!(seats)
    with_lock do
      raise "Not enough seats available" if available < seats

      self.available -= seats
      self.sold += seats
      save!
    end
  end

  # Record a refund (increase available, decrease sold)
  def record_refund!(seats)
    with_lock do
      raise "Cannot refund more than sold" if sold < seats

      self.available += seats
      self.sold -= seats
      save!
    end
  end

  # Hold seats (decrease available, increase held)
  def hold_seats!(seats)
    with_lock do
      raise "Not enough seats available" if available < seats

      self.available -= seats
      self.held += seats
      save!
    end
  end

  # Release held seats
  def release_hold!(seats)
    with_lock do
      raise "Cannot release more than held" if held < seats

      self.available += seats
      self.held -= seats
      save!
    end
  end

  # Sold percentage for this tier
  def sold_percentage
    return 0 if capacity.zero?

    (sold.to_f / capacity * 100).round(1)
  end

  private

  def ensure_defaults
    self.sold ||= 0
    self.held ||= 0
    self.available ||= capacity if capacity.present?
  end
end

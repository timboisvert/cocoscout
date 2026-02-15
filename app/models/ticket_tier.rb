# frozen_string_literal: true

class TicketTier < ApplicationRecord
  belongs_to :seating_configuration

  has_many :show_ticket_tiers, dependent: :nullify

  validates :name, presence: true
  validates :capacity, presence: true, numericality: { greater_than: 0 }
  validates :default_price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :position, presence: true, numericality: { greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(:position) }

  before_validation :set_position, on: :create

  def default_price
    default_price_cents / 100.0
  end

  def default_price=(value)
    self.default_price_cents = (value.to_f * 100).round
  end

  private

  def set_position
    return if position.present?

    max_position = seating_configuration&.ticket_tiers&.maximum(:position) || -1
    self.position = max_position + 1
  end
end

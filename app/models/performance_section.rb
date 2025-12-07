# frozen_string_literal: true

class PerformanceSection < ApplicationRecord
  belongs_to :profileable, polymorphic: true
  has_many :performance_credits, dependent: :destroy

  accepts_nested_attributes_for :performance_credits, allow_destroy: true

  validates :name, presence: true, length: { maximum: 50 }
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  default_scope { order(:position) }

  before_validation :set_default_position, on: :create
  before_validation :set_credit_profileable

  private

  def set_credit_profileable
    # Ensure all credits have the same profileable as their section
    performance_credits.each do |credit|
      credit.profileable = profileable if credit.profileable_id.nil?
    end
  end

  def set_default_position
    return if position.present?

    max_position = profileable&.performance_sections&.maximum(:position) || -1
    self.position = max_position + 1
  end
end

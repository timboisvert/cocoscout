# frozen_string_literal: true

class TrainingCredit < ApplicationRecord
  belongs_to :person

  # Validations
  validates :institution, presence: true, length: { maximum: 200 }
  validates :program, presence: true, length: { maximum: 200 }
  validates :notes, length: { maximum: 1000 }
  validates :year_start, presence: true, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 1900,
    less_than_or_equal_to: -> { Time.current.year + 5 }
  }
  validates :year_end, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 1900,
    less_than_or_equal_to: -> { Time.current.year + 5 },
    allow_nil: true
  }
  validate :year_end_after_year_start
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Scopes
  default_scope { order(:position) }

  # Callbacks
  before_validation :set_default_position, on: :create

  def display_year_range
    return year_start.to_s if year_end.blank?
    return year_start.to_s if year_start == year_end

    "#{year_start}-#{year_end}"
  end

  def display_year_range_with_present
    return year_start.to_s if year_end.present? && year_start == year_end
    return "#{year_start}-Present" if year_end.blank?

    "#{year_start}-#{year_end}"
  end

  private

  def year_end_after_year_start
    return if year_end.blank? || year_start.blank?

    return unless year_end < year_start

    errors.add(:year_end, "must be greater than or equal to start year")
  end

  def set_default_position
    return if position.present?

    max_position = person&.training_credits&.maximum(:position) || -1
    self.position = max_position + 1
  end
end

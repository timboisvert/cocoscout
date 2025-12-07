# frozen_string_literal: true

class PerformanceCredit < ApplicationRecord
  belongs_to :profileable, polymorphic: true
  belongs_to :performance_section, optional: true

  # Validations
  validates :title, presence: true, length: { maximum: 200 }
  validates :section_name, length: { maximum: 50 }, allow_blank: true
  validates :location, length: { maximum: 100 }, allow_blank: true
  validates :role, length: { maximum: 100 }, allow_blank: true
  validates :notes, length: { maximum: 1000 }, allow_blank: true
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
  scope :by_section, ->(section_id) { where(performance_section_id: section_id) }

  # Callbacks
  before_validation :set_default_position, on: :create

  def display_year_range
    return year_start.to_s if year_end.blank?
    return year_start.to_s if year_start == year_end

    "#{year_start}-#{year_end}"
  end

  def display_year_range_with_present
    return year_start.to_s if year_end.blank?
    return year_start.to_s if year_start == year_end

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

    max_position = if performance_section_id.present?
                     performance_section&.performance_credits&.maximum(:position) || -1
    else
                     profileable&.performance_credits&.where(section_name: section_name)&.maximum(:position) || -1
    end

    self.position = max_position + 1
  end
end

class PerformanceCredit < ApplicationRecord
  belongs_to :profileable, polymorphic: true

  # Validations
  validates :title, presence: true, length: { maximum: 200 }
  validates :section_name, length: { maximum: 50 }
  validates :venue, length: { maximum: 200 }
  validates :location, length: { maximum: 100 }
  validates :role, length: { maximum: 100 }
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
  default_scope { order(:section_name, :position) }

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
    if year_end < year_start
      errors.add(:year_end, "must be greater than or equal to start year")
    end
  end

  def set_default_position
    return if position.present?
    max_position = profileable&.performance_credits&.where(section_name: section_name)&.maximum(:position) || -1
    self.position = max_position + 1
  end
end

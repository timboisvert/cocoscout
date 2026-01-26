# frozen_string_literal: true

class LocationSpace < ApplicationRecord
  belongs_to :location

  has_many :space_rentals, dependent: :restrict_with_error
  has_many :shows, dependent: :nullify

  validates :name, presence: true

  # Ensure only one default space per location
  before_save :ensure_single_default
  after_create :set_as_default_if_only_space

  scope :by_name, -> { order(:name) }

  def display_name
    "#{location.name} - #{name}"
  end

  private

  def ensure_single_default
    return unless default?

    LocationSpace.where(location: location).where.not(id: id).update_all(default: false)
  end

  def set_as_default_if_only_space
    return unless location.location_spaces.count == 1

    update_column(:default, true)
  end
end

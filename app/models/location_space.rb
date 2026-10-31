# frozen_string_literal: true

# A room in a location (the interface says "room"; the model keeps its
# name). Rooms are on every plan: shows, rentals, classes and auditions use
# them, and Ticketing (Pro) reads them without the room ever reading
# Ticketing back (advanced ticketing plan §0). `capacity` is "most people
# allowed", a fact about the room, which Ticketing uses as a general
# admission cap when a production sets no counts.
class LocationSpace < ApplicationRecord
  belongs_to :location

  has_many :space_rentals, dependent: :restrict_with_error
  has_many :shows, dependent: :nullify
  has_many :access_answers, as: :owner, dependent: :destroy

  # Room-only accessibility facts (accessibility plan §1).
  STAGE_ACCESS = %w[ramp lift floor_level steps_only].freeze
  STAGE_ACCESS_LABELS = { "ramp" => "Ramp to the stage", "lift" => "Lift to the stage", "floor_level" => "Stage at floor level", "steps_only" => "Steps only" }.freeze
  validates :stage_access, inclusion: { in: STAGE_ACCESS }, allow_blank: true
  validates :wheelchair_spaces, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  def access_profile = AccessProfile.for(self)
  def stage_access_label = stage_access.present? ? STAGE_ACCESS_LABELS.fetch(stage_access) : nil

  validates :name, presence: true, length: { maximum: 80 }
  validates :capacity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  # Ensure only one default space per location
  before_save :ensure_single_default
  after_create :set_as_default_if_only_space

  scope :by_name, -> { order(:name) }

  def display_name
    "#{location.name} - #{name}"
  end

  # What's coming up in this room: shows, rehearsals, classes, every kind of
  # event on the calendar, soonest first.
  def upcoming_shows(limit: 20)
    shows.where(canceled: false).where("date_and_time >= ?", Time.current).includes(:production).order(:date_and_time).limit(limit)
  end

  def next_show
    upcoming_shows(limit: 1).first
  end

  # The one room can't be deleted; neither can one with bookings or shows.
  def deletable?
    space_rentals.none? && shows.none? && location.location_spaces.where.not(id: id).exists?
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

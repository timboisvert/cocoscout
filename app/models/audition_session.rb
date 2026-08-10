# frozen_string_literal: true

class AuditionSession < ApplicationRecord
  belongs_to :audition_cycle
  has_one :production, through: :audition_cycle
  has_many :auditions, dependent: :destroy
  has_many :audition_session_availabilities, dependent: :destroy
  belongs_to :location

  validates :start_at, presence: true
  validates :audition_cycle, presence: true
  validates :location, presence: true

  def display_name
    "#{production.name} - #{start_at.strftime('%-m/%-d/%Y %l:%M %p')}"
  end

  # ---- Open-signup slots ----
  # In open-signup mode each session is a bookable slot. maximum_auditionees is
  # the capacity (nil means unlimited).

  def signups_count
    auditions.count
  end

  def capacity
    maximum_auditionees
  end

  def full?
    capacity.present? && signups_count >= capacity
  end

  # nil when there's no capacity limit; otherwise the number of open spots.
  def spots_remaining
    return nil if capacity.nil?

    [ capacity - signups_count, 0 ].max
  end
end

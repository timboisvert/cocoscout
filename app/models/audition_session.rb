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
end

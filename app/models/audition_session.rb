class AuditionSession < ApplicationRecord
  belongs_to :call_to_audition
  has_one :production, through: :call_to_audition
  has_many :auditions, dependent: :destroy
  belongs_to :location

  validates :start_at, presence: true
  validates :call_to_audition, presence: true
  validates :location, presence: true

  def display_name
    "#{production.name} - #{start_at.strftime("%-m/%-d/%Y %l:%M %p")}"
  end

  def is_full?
    (maximum_auditionees && (auditions.count == maximum_auditionees))
  end

  def is_overbooked?
    (maximum_auditionees && (auditions.count > maximum_auditionees))
  end
end

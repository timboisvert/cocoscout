class AuditionSession < ApplicationRecord
  belongs_to :production
  has_and_belongs_to_many :auditions

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

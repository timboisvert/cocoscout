class ProfileResume < ApplicationRecord
  belongs_to :profileable, polymorphic: true
  has_one_attached :file

  validates :name, presence: true, length: { maximum: 100 }
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  default_scope { order(:position) }

  before_validation :set_default_position, on: :create

  private

  def set_default_position
    return if position.present?
    max_position = profileable&.profile_resumes&.maximum(:position) || -1
    self.position = max_position + 1
  end
end

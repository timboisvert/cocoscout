class ProfileHeadshot < ApplicationRecord
  belongs_to :profileable, polymorphic: true
  has_one_attached :image

  # Validations
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :max_headshots_per_profileable
  validate :only_one_primary_per_profileable
  validate :image_content_type

  # Scopes
  default_scope { order(:position) }
  scope :primary, -> { where(is_primary: true) }

  # Callbacks
  before_validation :set_default_position, on: :create

  private

  def set_default_position
    return if position.present?
    max_position = profileable&.profile_headshots&.maximum(:position) || -1
    self.position = max_position + 1
  end

  def max_headshots_per_profileable
    return unless profileable
    existing_count = profileable.profile_headshots.where.not(id: id).count
    if existing_count >= 10
      errors.add(:base, "Cannot have more than 10 headshots per profile")
    end
  end

  def only_one_primary_per_profileable
    return unless is_primary && profileable
    existing_primary = profileable.profile_headshots.where(is_primary: true).where.not(id: id)
    if existing_primary.exists?
      errors.add(:is_primary, "There can only be one primary headshot per profile")
    end
  end

  def image_content_type
    return unless image.attached?
    unless image.content_type.in?(%w[image/jpeg image/jpg image/png image/webp])
      errors.add(:image, "must be a JPEG, PNG, or WebP file")
    end
  end
end

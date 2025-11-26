class ProfileHeadshot < ApplicationRecord
  belongs_to :profileable, polymorphic: true
  has_one_attached :image do |attachable|
    attachable.variant :thumb, resize_to_limit: [ 100, 100 ], preprocessed: true
  end

  # Categories for headshot types
  CATEGORIES = %w[
    theatrical
    commercial
    character
    comedy
    dramatic
    period
    contemporary
    outdoor
    studio
    lifestyle
  ].freeze

  # Validations
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true
  validate :image_content_type

  # Scopes
  default_scope { order(:position) }
  scope :primary, -> { where(is_primary: true) }

  # Callbacks
  before_validation :set_default_position, on: :create
  before_validation :clear_other_primaries, if: -> { is_primary == true }
  after_create :set_as_primary_if_first
  after_destroy :set_new_primary_if_needed

  private

  def set_default_position
    return if position.present?
    max_position = profileable&.profile_headshots&.maximum(:position) || -1
    self.position = max_position + 1
  end

  def set_as_primary_if_first
    # If this is the first headshot and no primary is set, make it primary
    if profileable && profileable.profile_headshots.count == 1 && !is_primary
      update_column(:is_primary, true)
    end
  end

  def set_new_primary_if_needed
    # If the destroyed headshot was primary, set the first remaining headshot as primary
    return unless is_primary && profileable
    return if destroyed? # Don't try to update if already destroyed

    first_remaining = profileable.profile_headshots.where.not(id: id).first
    if first_remaining
      first_remaining.update_column(:is_primary, true)
    end
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

  def clear_other_primaries
    return unless profileable
    Rails.logger.info "Clearing other primaries for headshot #{id}, is_primary: #{is_primary}"
    result = profileable.profile_headshots.where.not(id: id).update_all(is_primary: false)
    Rails.logger.info "Cleared #{result} other primaries"
  end

  def image_content_type
    return unless image.attached?
    unless image.content_type.in?(%w[image/jpeg image/jpg image/png])
      errors.add(:image, "must be a JPG, JPEG, or PNG file")
    end
  end
end

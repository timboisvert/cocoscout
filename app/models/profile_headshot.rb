# frozen_string_literal: true

class ProfileHeadshot < ApplicationRecord
  include HierarchicalStorageKey

  belongs_to :profileable, polymorphic: true
  has_one_attached :image do |attachable|
    attachable.variant :thumb, resize_to_limit: [ 100, 100 ], preprocessed: true
    attachable.variant :small, resize_to_limit: [ 128, 128 ], preprocessed: true
    attachable.variant :tile, resize_to_limit: [ 300, 300 ], preprocessed: true
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

  # Safely get an image variant, returning nil if the image can't be processed
  def safe_image_variant(variant_name)
    return nil unless image.attached?

    image.variant(variant_name)
  rescue ActiveStorage::InvariableError, ActiveStorage::FileNotFoundError => e
    Rails.logger.error("Failed to generate variant for profile_headshot #{id} image: #{e.message}")
    nil
  end

  # Callbacks
  before_validation :set_default_position, on: :create
  before_validation :clear_other_primaries, if: -> { is_primary == true }
  after_create :set_as_primary_if_first
  after_destroy :set_new_primary_if_needed
  after_commit :invalidate_profileable_cache

  private

  # Invalidate the parent person/group cache when headshot changes
  def invalidate_profileable_cache
    return unless profileable.respond_to?(:invalidate_cache)

    profileable.invalidate_cache(:person_card) if profileable.is_a?(Person)
    profileable.invalidate_cache(:person_profile) if profileable.is_a?(Person)
    profileable.invalidate_cache(:group_card) if profileable.is_a?(Group)
    profileable.invalidate_cache(:group_profile) if profileable.is_a?(Group)
  end

  def set_default_position
    return if position.present?

    max_position = profileable&.profile_headshots&.maximum(:position) || -1
    self.position = max_position + 1
  end

  def set_as_primary_if_first
    # If this is the first headshot and no primary is set, make it primary
    return unless profileable && profileable.profile_headshots.count == 1 && !is_primary

    update_column(:is_primary, true)
  end

  def set_new_primary_if_needed
    # If the destroyed headshot was primary, set the first remaining headshot as primary
    return unless is_primary && profileable
    return if destroyed? # Don't try to update if already destroyed

    first_remaining = profileable.profile_headshots.where.not(id: id).first
    return unless first_remaining

    first_remaining.update_column(:is_primary, true)
  end

  def max_headshots_per_profileable
    return unless profileable

    existing_count = profileable.profile_headshots.where.not(id: id).count
    return unless existing_count >= 10

    errors.add(:base, "Cannot have more than 10 headshots per profile")
  end

  def only_one_primary_per_profileable
    return unless is_primary && profileable

    existing_primary = profileable.profile_headshots.where(is_primary: true).where.not(id: id)
    return unless existing_primary.exists?

    errors.add(:is_primary, "There can only be one primary headshot per profile")
  end

  def clear_other_primaries
    return unless profileable

    Rails.logger.info "Clearing other primaries for headshot #{id}, is_primary: #{is_primary}"
    result = profileable.profile_headshots.where.not(id: id).update_all(is_primary: false)
    Rails.logger.info "Cleared #{result} other primaries"
  end

  def image_content_type
    return unless image.attached?

    return if image.content_type.in?(%w[image/jpeg image/jpg image/png])

    errors.add(:image, "must be a JPG, JPEG, or PNG file")
  end
end

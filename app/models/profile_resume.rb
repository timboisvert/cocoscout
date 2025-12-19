# frozen_string_literal: true

class ProfileResume < ApplicationRecord
  include HierarchicalStorageKey

  belongs_to :profileable, polymorphic: true
  has_one_attached :file

  validate :acceptable_file
  validates :name, presence: true, length: { maximum: 100 }
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  default_scope { order(:position) }

  before_validation :set_default_position, on: :create
  before_validation :set_default_name, on: :create
  after_commit :invalidate_profileable_cache

  private

  # Invalidate the parent person/group cache when resume changes
  def invalidate_profileable_cache
    return unless profileable.respond_to?(:invalidate_cache)

    profileable.invalidate_cache(:person_card) if profileable.is_a?(Person)
    profileable.invalidate_cache(:person_profile) if profileable.is_a?(Person)
    profileable.invalidate_cache(:group_card) if profileable.is_a?(Group)
    profileable.invalidate_cache(:group_profile) if profileable.is_a?(Group)
  end

  def set_default_position
    return if position.present?

    max_position = profileable&.profile_resumes&.maximum(:position) || -1
    self.position = max_position + 1
  end

  def set_default_name
    return if name.present?
    return unless file.attached?

    self.name = file.filename.to_s
  end

  def acceptable_file
    return unless file.attached?

    return if file.content_type.in?(%w[application/pdf image/jpeg image/jpg image/png])

    errors.add(:file, "must be a PDF, JPG, or PNG file")
  end
end

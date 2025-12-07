# frozen_string_literal: true

class Show < ApplicationRecord
  include HierarchicalStorageKey

  belongs_to :production
  belongs_to :location, optional: true

  has_many :show_person_role_assignments, lambda {
    joins(:role).order(Arel.sql("roles.position ASC, roles.created_at ASC"))
  }, dependent: :destroy

  # Polymorphic associations for cast members (people or groups)
  has_many :cast_people, lambda {
    where(show_person_role_assignments: { assignable_type: "Person" })
  }, through: :show_person_role_assignments, source: :assignable, source_type: "Person"
  has_many :cast_groups, lambda {
    where(show_person_role_assignments: { assignable_type: "Group" })
  }, through: :show_person_role_assignments, source: :assignable, source_type: "Group"

  # Convenience methods for backward compatibility
  has_many :people, through: :show_person_role_assignments, source: :assignable, source_type: "Person"
  has_many :roles, through: :show_person_role_assignments

  has_many :show_links, dependent: :destroy
  accepts_nested_attributes_for :show_links, allow_destroy: true

  has_one_attached :poster, dependent: :purge_later do |attachable|
    attachable.variant :small, resize_to_limit: [ 200, 300 ], preprocessed: true
  end

  has_many :show_availabilities, dependent: :destroy
  has_many :available_people, through: :show_availabilities, source: :person

  # Event types are defined in config/event_types.yml
  enum :event_type, EventTypes.enum_hash

  validates :event_type, presence: true
  validates :date_and_time, presence: true
  validate :poster_content_type
  validate :location_or_online_required

  # Cache invalidation - invalidate production dashboard when show changes
  after_commit :invalidate_production_caches

  # Scope to find all shows in a recurrence group
  scope :in_recurrence_group, ->(group_id) { where(recurrence_group_id: group_id) }

  # Check if this show is part of a recurring series
  def recurring?
    recurrence_group_id.present?
  end

  # Get all shows in the same recurrence group
  def recurrence_siblings
    return Show.none unless recurring?

    Show.in_recurrence_group(recurrence_group_id).where.not(id: id)
  end

  # Get all shows in the recurrence group including self
  def recurrence_group
    return Show.none unless recurring?

    Show.in_recurrence_group(recurrence_group_id)
  end

  def safe_poster_variant(variant_name)
    return nil unless poster.attached?

    poster.variant(variant_name)
  rescue ActiveStorage::InvariableError, ActiveStorage::FileNotFoundError => e
    Rails.logger.error("Failed to generate variant for show #{id} poster: #{e.message}")
    nil
  end

  private

  def invalidate_production_caches
    # Invalidate production dashboard cache when show changes
    Rails.cache.delete("production_dashboard_#{production_id}")
    # NOTE: show_info_card uses cache key versioning with updated_at,
    # so it auto-invalidates when show.updated_at changes
  end

  def poster_content_type
    return unless poster.attached? && !poster.content_type.in?(%w[image/jpeg image/jpg image/png])

    errors.add(:poster, "Poster must be a JPEG, JPG, or PNG file")
  end

  def location_or_online_required
    return if location.present? || location_id.present? || is_online?

    errors.add(:base, "Please select a location or mark this event as online")
  end
end

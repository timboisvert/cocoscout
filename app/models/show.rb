# frozen_string_literal: true

class Show < ApplicationRecord
  include HierarchicalStorageKey

  belongs_to :production
  belongs_to :location, optional: true
  belongs_to :event_linkage, optional: true

  has_many :show_person_role_assignments, dependent: :destroy

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

  # Show-specific roles (roles where show_id = this show's id)
  has_many :custom_roles, -> { where.not(show_id: nil) }, class_name: "Role", dependent: :destroy

  has_many :show_links, dependent: :destroy
  accepts_nested_attributes_for :show_links, allow_destroy: true

  has_one_attached :poster, dependent: :purge_later do |attachable|
    attachable.variant :small, resize_to_limit: [ 200, 300 ], preprocessed: true
  end

  has_many :show_availabilities, dependent: :destroy
  has_many :available_people, through: :show_availabilities, source: :person

  has_many :role_vacancies, dependent: :destroy

  has_many :show_cast_notifications, dependent: :destroy

  # Linkage roles
  enum :linkage_role, { sibling: "sibling", child: "child" }, prefix: :linkage

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

  # Event Linkage methods

  # Check if this show is linked to other shows
  def linked?
    event_linkage_id.present?
  end

  # Get all other shows in the same linkage (excluding self)
  def linked_shows
    return Show.none unless linked?

    event_linkage.shows.where.not(id: id).order(:date_and_time)
  end

  # Get sibling shows in the same linkage (excluding self if sibling)
  def linked_siblings
    return Show.none unless linked?

    event_linkage.sibling_shows.where.not(id: id).order(:date_and_time)
  end

  # Get child shows in the same linkage
  def linked_children
    return Show.none unless linked?

    event_linkage.child_shows.order(:date_and_time)
  end

  # Check if this show is the primary (first sibling)
  def primary_linked_show?
    return false unless linked? && linkage_sibling?

    event_linkage.sibling_shows.order(:date_and_time).first == self
  end

  # Determine if this show should be visible on the production's public profile
  # Cascade: individual show override > production event type override > global event type default
  def public_profile_visible?
    # If show has explicit override, use it
    return public_profile_visible unless public_profile_visible.nil?

    # Otherwise, check production's event type override
    production.event_type_publicly_visible?(event_type)
  end

  # Check if this show is in the past
  def past?
    date_and_time < Time.current
  end

  # Check if casting has been finalized for this show
  def casting_finalized?
    casting_finalized_at.present?
  end

  # Reopen casting for this show (clears finalization date)
  def reopen_casting!
    update!(casting_finalized_at: nil)
  end

  # Finalize casting and record the timestamp
  def finalize_casting!
    update!(casting_finalized_at: Time.current)
  end

  # Check if show is fully cast (all roles have assignments)
  def fully_cast?
    available_roles.count == show_person_role_assignments.count
  end

  # Get assignables that were previously notified as cast but are no longer in current cast
  def removed_cast_members
    # Get all assignables from previous cast notifications
    previously_notified = show_cast_notifications.cast_notifications
                                                  .pluck(:assignable_type, :assignable_id)
                                                  .map { |type, id| [ type, id ] }
                                                  .to_set

    # Get current cast assignments
    current_cast = show_person_role_assignments
                     .pluck(:assignable_type, :assignable_id)
                     .map { |type, id| [ type, id ] }
                     .to_set

    # Find who was previously notified but is no longer in current cast
    removed = previously_notified - current_cast

    # Load the actual assignable objects
    removed.map do |type, id|
      type.constantize.find_by(id: id)
    end.compact
  end

  # Get current cast members who haven't been notified yet
  def unnotified_cast_members
    # Get all assignables from current cast
    current_cast = show_person_role_assignments
                     .pluck(:assignable_type, :assignable_id)
                     .map { |type, id| [ type, id ] }
                     .to_set

    # Get all assignables already notified as cast
    already_notified = show_cast_notifications.cast_notifications
                                               .pluck(:assignable_type, :assignable_id)
                                               .map { |type, id| [ type, id ] }
                                               .to_set

    # Find who is in current cast but hasn't been notified
    unnotified = current_cast - already_notified

    # Load the actual assignable objects with their assignments
    show_person_role_assignments.select do |assignment|
      unnotified.include?([ assignment.assignable_type, assignment.assignable_id ])
    end
  end

  def safe_poster_variant(variant_name)
    return nil unless poster.attached?

    poster.variant(variant_name)
  rescue ActiveStorage::InvariableError, ActiveStorage::FileNotFoundError => e
    Rails.logger.error("Failed to generate variant for show #{id} poster: #{e.message}")
    nil
  end

  # Cache key for public show page
  def public_show_cache_key
    "show_public_page_v1_#{id}"
  end

  # ETag for HTTP caching on public show page
  def public_show_etag
    Digest::MD5.hexdigest([
      id,
      updated_at.to_i,
      production.updated_at.to_i,
      location&.updated_at&.to_i
    ].compact.join("-"))
  end

  # Returns the roles available for this show.
  # If use_custom_roles is true, returns show-specific roles.
  # Otherwise, returns the production's roles.
  def available_roles
    if use_custom_roles?
      custom_roles
    else
      production.roles.production_roles
    end
  end

  # Copy all production roles to this show's custom roles
  def copy_roles_from_production!
    production.roles.production_roles.each do |role|
      new_role = custom_roles.create!(
        name: role.name,
        position: role.position,
        restricted: role.restricted,
        production: production
      )

      # Copy role eligibilities if restricted
      if role.restricted?
        role.role_eligibilities.each do |eligibility|
          new_role.role_eligibilities.create!(
            member_type: eligibility.member_type,
            member_id: eligibility.member_id
          )
        end
      end
    end
  end

  private

  def invalidate_production_caches
    # Invalidate production dashboard cache when show changes
    Rails.cache.delete("production_dashboard_#{production_id}")
    # Invalidate production public profile cache
    Rails.cache.delete(production.public_profile_cache_key) if production
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

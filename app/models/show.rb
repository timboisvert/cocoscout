# frozen_string_literal: true

class Show < ApplicationRecord
  include HierarchicalStorageKey

  belongs_to :production
  belongs_to :location, optional: true
  belongs_to :event_linkage, optional: true

  # A show may be referenced as the primary_show in an EventLinkage
  has_one :primary_event_linkage, class_name: "EventLinkage", foreign_key: :primary_show_id, dependent: :nullify

  has_many :email_drafts, dependent: :nullify

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
  has_many :role_vacancy_shows, dependent: :destroy

  has_many :show_cast_notifications, dependent: :destroy

  # Sign-up forms can be associated with specific shows
  has_many :sign_up_forms, dependent: :destroy
  has_many :sign_up_form_instances, dependent: :destroy
  has_many :sign_up_form_shows, dependent: :destroy

  # Linkage roles
  enum :linkage_role, { sibling: "sibling", child: "child" }, prefix: :linkage

  # Casting source determines how performers are assigned to this show
  # nil means "inherit from production"
  enum :casting_source, {
    talent_pool: "talent_pool",   # Traditional casting from production members
    sign_up: "sign_up",           # Self-service registration via sign-up forms
    manual: "manual",             # Admin manually adds names/emails
    hybrid: "hybrid"              # All sources: talent pool + sign-up + manual
  }, default: nil, prefix: :casting

  # Returns the effective casting source (inheriting from production if not overridden)
  def effective_casting_source
    casting_source || production&.casting_source || "talent_pool"
  end

  # Check if this show uses a custom casting source (overriding production default)
  def uses_custom_casting_source?
    casting_source.present?
  end

  # Event types are defined in config/event_types.yml
  enum :event_type, EventTypes.enum_hash

  validates :event_type, presence: true
  validates :date_and_time, presence: true
  validate :poster_content_type
  validate :location_or_online_required

  # Cache invalidation - invalidate production dashboard when show changes
  after_commit :invalidate_production_caches

  # Calendar sync - trigger sync for affected people when show changes
  after_commit :trigger_calendar_sync, on: [ :create, :update ]
  after_destroy :trigger_calendar_sync_for_destruction

  # Sign-up form instance management
  after_commit :create_sign_up_form_instances, on: :create
  after_commit :sync_sign_up_form_instances_on_cancel, on: :update, if: :saved_change_to_canceled?
  after_commit :sync_sign_up_form_instances_on_date_change, on: :update, if: :saved_change_to_date_and_time?
  before_destroy :cleanup_sign_up_form_instances

  # Nullify primary_show_id references before destruction to avoid FK constraint errors
  before_destroy :nullify_primary_show_references

  # Clear assignments when toggling custom roles
  before_save :clear_assignments_on_custom_roles_toggle, if: :use_custom_roles_changed?

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

  # Display name with date for select dropdowns
  def name_with_date
    name = secondary_name.presence || event_type&.titleize || "Show"
    "#{name} - #{date_and_time&.strftime('%b %-d, %Y at %-I:%M %p')}"
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

  # Check if show is fully cast (all role slots have assignments)
  def fully_cast?
    total_slots = available_roles.sum(:quantity)
    total_slots == show_person_role_assignments.count
  end

  # Returns casting progress for this show
  def casting_progress
    total_slots = available_roles.sum(:quantity)
    filled_slots = show_person_role_assignments.count
    {
      total: total_slots,
      filled: filled_slots,
      percentage: total_slots > 0 ? (filled_slots.to_f / total_slots * 100).round : 0
    }
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
        production: production,
        # Multi-person and category fields
        quantity: role.quantity,
        category: role.category,
        # Payment fields
        payment_type: role.payment_type,
        payment_amount: role.payment_amount,
        payment_rate: role.payment_rate,
        payment_minimum: role.payment_minimum
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

  # Get vacancies where the person can't make this show but is still cast.
  # Includes:
  # - Cancelled vacancies (producer chose "don't find a replacement" for linked events)
  # - Open vacancies (looking for replacement but not filled yet)
  # Does NOT include filled or cancelled vacancies.
  # Filled = someone else claimed the role
  # Cancelled = the person reclaimed their spot (they can make it now)
  # Returns a hash: { [role_id, assignable_type, assignable_id] => vacancy }
  def cant_make_it_vacancies_by_assignment
    # Find vacancies where someone can't make it - includes:
    # - open: vacancy created, looking for replacement
    # - finding_replacement: actively seeking replacement
    # - not_filling: producer decided not to fill, person still can't make it
    # Does NOT include:
    # - filled: someone else claimed the role
    # - cancelled: the person reclaimed their spot (they can now make it)
    vacancies = RoleVacancy
      .where(status: %w[open finding_replacement not_filling])
      .joins("LEFT JOIN role_vacancy_shows ON role_vacancy_shows.role_vacancy_id = role_vacancies.id")
      .where("role_vacancies.show_id = ? OR role_vacancy_shows.show_id = ?", id, id)
      .includes(:role, :affected_shows)
      .distinct

    # Build lookup hash keyed by [role_id, assignable_type, assignable_id]
    result = {}
    vacancies.each do |vacancy|
      # Check if this specific show is affected (for linked events)
      affected_show_ids = vacancy.affected_shows.pluck(:id)
      is_affected = affected_show_ids.empty? || affected_show_ids.include?(id) || vacancy.show_id == id

      next unless is_affected && vacancy.vacated_by.present?

      key = [ vacancy.role_id, vacancy.vacated_by_type, vacancy.vacated_by_id ]
      result[key] = vacancy
    end
    result
  end

  # Alias for backward compatibility
  alias_method :cancelled_vacancies_by_assignment, :cant_make_it_vacancies_by_assignment

  private

  def create_sign_up_form_instances
    # Find all repeated forms for this production that match this show
    production.sign_up_forms.repeated.active.find_each do |form|
      form.create_instance_for_show!(self) if form.matches_event?(self)
    end
  end

  def sync_sign_up_form_instances_on_cancel
    # When a show is canceled, cancel all its sign-up form instances
    if canceled?
      SignUpFormInstance.where(show_id: id).find_each do |instance|
        instance.update!(status: "cancelled") unless instance.cancelled?
      end
    else
      # If uncanceled, set to initializing and let the job determine actual state
      SignUpFormInstance.where(show_id: id, status: "cancelled").find_each do |instance|
        instance.update!(status: "initializing")
      end
      # Run status job to calculate correct state based on current time
      UpdateSignUpStatusesJob.perform_now
    end
  end

  def sync_sign_up_form_instances_on_date_change
    # When a show's date/time changes, recalculate opens_at, closes_at, edit_cutoff_at for all instances
    SignUpFormInstance.where(show_id: id).find_each do |instance|
      form = instance.sign_up_form
      service = SlotManagementService.new(form)

      new_opens_at = service.send(:calculate_opens_at, self)
      new_closes_at = service.send(:calculate_closes_at, self)
      new_edit_cutoff_at = service.send(:calculate_edit_cutoff_at, self)

      # Update the instance with recalculated dates and reset status to recalculate
      instance.update!(
        opens_at: new_opens_at,
        closes_at: new_closes_at,
        edit_cutoff_at: new_edit_cutoff_at,
        status: "initializing"
      )
    end

    # Run status job to calculate correct state based on current time
    UpdateSignUpStatusesJob.perform_now
  end

  def cleanup_sign_up_form_instances
    # When a show is deleted, destroy all its sign-up form instances
    # This cascades to slots and registrations via dependent: :destroy
    SignUpFormInstance.where(show_id: id).destroy_all
  end

  def invalidate_production_caches
    # Invalidate production dashboard cache when show changes
    Rails.cache.delete("production_dashboard_#{production_id}")
    # Invalidate production public profile cache
    Rails.cache.delete(production.public_profile_cache_key) if production
    # NOTE: show_info_card uses cache key versioning with updated_at,
    # so it auto-invalidates when show.updated_at changes
  end

  def nullify_primary_show_references
    # Explicitly nullify any event linkages that reference this show as primary_show
    # This is needed because dependent: :nullify on has_one may not work with destroy_all
    EventLinkage.where(primary_show_id: id).update_all(primary_show_id: nil)
  end

  def poster_content_type
    return unless poster.attached? && !poster.content_type.in?(%w[image/jpeg image/jpg image/png])

    errors.add(:poster, "Poster must be a JPEG, JPG, or PNG file")
  end

  def location_or_online_required
    return if location.present? || location_id.present? || is_online?

    errors.add(:base, "Please select a location or mark this event as online")
  end

  def clear_assignments_on_custom_roles_toggle
    # Get all shows that need to be cleared (this show + linked shows)
    shows_to_clear = if linked?
      event_linkage.shows.to_a
    else
      [ self ]
    end

    # Determine if we're toggling OFF (switching to production roles)
    toggling_off = !use_custom_roles?

    shows_to_clear.each do |show_to_clear|
      # Clear all assignments for the show
      show_to_clear.show_person_role_assignments.destroy_all

      # Update linked shows (but not this show - it will be saved with the record)
      if show_to_clear != self
        # Delete custom roles if toggling OFF
        show_to_clear.custom_roles.destroy_all if toggling_off

        # Sync the use_custom_roles flag and clear finalized status
        show_to_clear.update_columns(
          use_custom_roles: use_custom_roles?,
          casting_finalized_at: nil
        )
      end
    end

    # Also unmark this show as finalized (will be saved with the record)
    self.casting_finalized_at = nil
  end

  def trigger_calendar_sync
    # Find all people who might have this show in their calendar sync
    # This includes:
    # 1. People assigned to this show
    # 2. People in the talent pool for this production (if they sync "all")
    person_ids = affected_person_ids_for_calendar_sync

    # Queue sync jobs for each person's subscriptions
    CalendarSubscription.enabled.where(person_id: person_ids).find_each do |subscription|
      CalendarSyncJob.perform_later(subscription.id)
    end
  end

  def trigger_calendar_sync_for_destruction
    # Before the show is destroyed, find the relevant calendar events and delete them
    CalendarEvent.where(show_id: id).find_each do |calendar_event|
      begin
        service = calendar_service_for(calendar_event.calendar_subscription)
        service&.delete_event(calendar_event)
      rescue StandardError => e
        Rails.logger.error("Failed to delete calendar event #{calendar_event.id}: #{e.message}")
        # Still destroy the calendar event record even if external deletion fails
        calendar_event.destroy
      end
    end
  end

  def affected_person_ids_for_calendar_sync
    person_ids = Set.new

    # People directly assigned to this show
    show_person_role_assignments.where(assignable_type: "Person").pluck(:assignable_id).each do |id|
      person_ids << id
    end

    # People in groups assigned to this show
    group_ids = show_person_role_assignments.where(assignable_type: "Group").pluck(:assignable_id)
    GroupMembership.where(group_id: group_ids).pluck(:person_id).each do |id|
      person_ids << id
    end

    # People in the production's talent pool (they might have "talent_pool" sync scope)
    talent_pool = production.talent_pool
    if talent_pool
      TalentPoolMembership.where(talent_pool_id: talent_pool.id, member_type: "Person").pluck(:member_id).each do |id|
        person_ids << id
      end

      # People in groups that are in the talent pool
      group_ids_in_pool = TalentPoolMembership.where(talent_pool_id: talent_pool.id, member_type: "Group").pluck(:member_id)
      GroupMembership.where(group_id: group_ids_in_pool).pluck(:person_id).each do |id|
        person_ids << id
      end
    end

    person_ids.to_a
  end

  def calendar_service_for(subscription)
    case subscription.provider
    when "google"
      CalendarSync::GoogleService.new(subscription)
    else
      nil # iCal doesn't need event deletion
    end
  end
end

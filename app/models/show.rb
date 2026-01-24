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

  # Payouts
  has_one :show_financials, dependent: :destroy
  has_one :show_payout, dependent: :destroy
  has_one :ticketing_show_link, dependent: :destroy
  has_many :production_expense_allocations, dependent: :destroy

  # Attendance tracking
  has_many :show_attendance_records, dependent: :destroy

  # Linkage roles
  enum :linkage_role, { sibling: "sibling", child: "child" }, prefix: :linkage

  # Casting source determines how performers are assigned to this show
  # nil means "inherit from production"
  # Talent pool now includes click-to-add functionality (formerly hybrid behavior)
  enum :casting_source, {
    talent_pool: "talent_pool",   # Traditional casting from production members (with click-to-add)
    sign_up: "sign_up",           # Self-service registration via sign-up forms
    manual: "manual"              # Admin manually adds names/emails
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

  # Check if this event type typically generates revenue (shows, classes, workshops)
  # This can be overridden by the non_revenue_override flag on ShowFinancials
  def revenue_event?
    # If marked as non-revenue override, it's not a revenue event
    return false if show_financials&.non_revenue_override?

    EventTypes.revenue_event_default(event_type)
  end

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

  # Clear assignments when toggling custom roles (unless migration is handling it)
  attr_accessor :skip_assignment_clear_on_role_toggle
  before_save :clear_assignments_on_custom_roles_toggle, if: :should_clear_assignments_on_toggle?

  # Set default attendance_enabled based on event type
  before_validation :set_attendance_enabled_default, on: :create

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

  # Check if this show has any linked sign-up forms
  def has_sign_up_form?
    sign_up_form_instances.exists?
  end

  # Get all confirmed sign-up registrations for this show
  # Returns registrations with person and slot preloaded
  def sign_up_registrations
    SignUpRegistration
      .joins(sign_up_slot: :sign_up_form_instance)
      .where(sign_up_form_instances: { show_id: id })
      .where(status: %w[confirmed waitlisted])
      .includes(:person, sign_up_slot: { sign_up_form_instance: :sign_up_form })
      .order(:position)
  end

  # Signup-based casting - pulls attendees from sign-up form registrations
  # Returns the sign-up form instance(s) associated with this show
  def sign_up_form_instances_for_casting
    sign_up_form_instances.includes(:sign_up_form)
  end

  # Find or create the system-managed Attendees role for signup-based casting
  def attendees_role
    return nil unless signup_based_casting?
    custom_roles.find_by(system_managed: true, system_role_type: "attendees")
  end

  # Sync attendees from sign-up form registrations
  def sync_attendees_from_signups!
    return 0 unless signup_based_casting?

    # Ensure we have the attendees role
    role = attendees_role || create_attendees_role!

    # Get all confirmed registrations from sign-up form instances for this show
    registrations = SignUpRegistration.joins(sign_up_slot: :sign_up_form_instance)
                                       .where(sign_up_form_instances: { show_id: id })
                                       .where(status: %w[confirmed waitlisted])
                                       .includes(:person)

    # Get current assignment person IDs
    current_person_ids = show_person_role_assignments.where(role: role).pluck(:assignable_id)
    registration_person_ids = registrations.map(&:person_id).uniq

    # Remove assignments for people who are no longer registered
    show_person_role_assignments.where(role: role)
                                 .where.not(assignable_id: registration_person_ids)
                                 .destroy_all

    # Add assignments for new registrations
    new_person_ids = registration_person_ids - current_person_ids
    new_person_ids.each do |person_id|
      show_person_role_assignments.create!(
        role: role,
        assignable_type: "Person",
        assignable_id: person_id
      )
    end

    # Update role quantity to match sign-up form capacity
    update_attendees_role_quantity!

    # Return the count of synced registrations
    registration_person_ids.count
  end

  # Enable signup-based casting
  def enable_signup_based_casting!
    return { success: true, synced_count: 0, message: "Already enabled" } if signup_based_casting?

    begin
      # Must use custom roles for signup-based casting
      self.use_custom_roles = true unless use_custom_roles?
      self.signup_based_casting = true
      save!(validate: false) # Skip validation as we're just updating flags

      create_attendees_role!
      synced_count = sync_attendees_from_signups!

      { success: true, synced_count: synced_count || 0 }
    rescue => e
      Rails.logger.error("Failed to enable signup-based casting: #{e.message}")
      { success: false, error: e.message }
    end
  end

  # Disable signup-based casting
  def disable_signup_based_casting!
    return { success: true, message: "Already disabled" } unless signup_based_casting?

    begin
      # Remove the attendees role and its assignments
      if attendees_role.present?
        attendees_role.destroy!
      end

      self.signup_based_casting = false
      save!(validate: false) # Skip validation as we're just updating flags

      { success: true }
    rescue => e
      Rails.logger.error("Failed to disable signup-based casting: #{e.message}")
      { success: false, error: e.message }
    end
  end

  # Check if signup-based casting is effectively enabled (considers production default)
  def effective_signup_based_casting?
    # If show has explicit setting, use it; otherwise use production default
    if signup_based_casting.nil?
      production&.default_signup_based_casting || false
    else
      signup_based_casting
    end
  end

  # Check if show overrides the production default for signup-based casting
  def overrides_signup_based_casting?
    !signup_based_casting.nil? && signup_based_casting != production&.default_signup_based_casting
  end

  # Attendance tracking helpers
  def attendance_enabled_default?
    # Check production default first, then fall back to event type
    return production.default_attendance_enabled if production&.default_attendance_enabled?
    %w[class workshop open_mic].include?(event_type)
  end

  # Check if attendance is effectively enabled (considers production default)
  def effective_attendance_enabled?
    # If show has explicit setting, use it; otherwise use production default or event type default
    if attendance_enabled.nil?
      attendance_enabled_default?
    else
      attendance_enabled
    end
  end

  # Check if show overrides the production default for attendance
  def overrides_attendance?
    !attendance_enabled.nil? && attendance_enabled != attendance_enabled_default?
  end

  # Get or initialize attendance records for all cast members
  # Returns array of { assignment:, record:, person: } hashes
  def attendance_records_for_all_cast
    records = []

    # Add cast members (show_person_role_assignments)
    show_person_role_assignments.includes(:role).each do |assignment|
      record = show_attendance_records.find_or_initialize_by(show_person_role_assignment: assignment)
      records << {
        assignment: assignment,
        record: record,
        person: assignment.person,
        type: "cast"
      }
    end

    # Add sign-up registrations (attendees)
    sign_up_registrations.includes(:person).each do |registration|
      person = registration.person
      sign_up_form = registration.sign_up_form_instance&.sign_up_form
      # Create a pseudo-assignment object for sign-up registrations
      pseudo_assignment = Struct.new(:id, :role, :person).new(
        "signup_#{registration.id}",
        Struct.new(:name).new(sign_up_form&.name || "Sign-up"),
        person
      )

      # Find or initialize attendance record for this sign-up
      record = show_attendance_records.find_or_initialize_by(sign_up_registration: registration)

      records << {
        assignment: pseudo_assignment,
        record: record,
        person: person,
        registration_id: registration.id,
        type: "signup"
      }
    end

    records
  end

  # Calculate attendance summary
  def attendance_summary
    records = show_attendance_records
    total_people = show_person_role_assignments.count + sign_up_registrations.count
    {
      total: total_people,
      present: records.present.count,
      absent: records.absent.count,
      late: records.late.count,
      excused: records.excused.count,
      unknown: total_people - records.count + records.unknown.count
    }
  end

  private

  def set_attendance_enabled_default
    return if attendance_enabled.present? # Don't override if explicitly set
    self.attendance_enabled = attendance_enabled_default?
  end

  def create_attendees_role!
    # Determine capacity from sign-up form
    form_instance = sign_up_form_instances.first
    capacity = form_instance&.sign_up_form&.capacity || 20

    custom_roles.create!(
      name: "Attendees",
      position: custom_roles.maximum(:position).to_i + 1,
      quantity: capacity,
      category: "performing",
      restricted: false,
      production: production,
      system_managed: true,
      system_role_type: "attendees"
    )
  end

  def update_attendees_role_quantity!
    return unless attendees_role

    form_instance = sign_up_form_instances.first
    capacity = form_instance&.sign_up_form&.capacity || 20

    attendees_role.update!(quantity: capacity) if attendees_role.quantity != capacity
  end

  public

  # Copy all production roles to this show's custom roles
  def copy_roles_from_production!
    production.roles.production_roles.each do |role|
      # For restricted roles, get the eligibilities to copy
      eligibilities_to_copy = role.restricted? ? role.role_eligibilities.to_a : []

      # Only mark as restricted if there are actual eligibilities
      # (a restricted role without eligibilities is invalid)
      should_be_restricted = role.restricted? && eligibilities_to_copy.any?

      new_role = custom_roles.new(
        name: role.name,
        position: role.position,
        restricted: should_be_restricted,
        production: production,
        # Multi-person and category fields
        quantity: role.quantity,
        category: role.category
      )

      # Set pending eligible member IDs to pass validation for restricted roles
      if should_be_restricted
        new_role.pending_eligible_member_ids = eligibilities_to_copy.map { |e| "#{e.member_type}_#{e.member_id}" }
      end

      new_role.save!

      # Copy role eligibilities after save
      if should_be_restricted
        eligibilities_to_copy.each do |eligibility|
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

  # Determine if we should clear assignments when toggling custom roles
  def should_clear_assignments_on_toggle?
    use_custom_roles_changed? && !skip_assignment_clear_on_role_toggle
  end

  def trigger_calendar_sync
    # Don't sync calendar for past shows
    return if date_and_time < Time.current

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

    # People in the production's effective talent pool (they might have "talent_pool" sync scope)
    talent_pool = production.effective_talent_pool
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

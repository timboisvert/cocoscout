# frozen_string_literal: true

class SignUpForm < ApplicationRecord
  belongs_to :production
  belongs_to :show, optional: true

  # New instance-based associations
  has_many :sign_up_form_instances, dependent: :destroy
  has_many :sign_up_form_shows, dependent: :destroy
  has_many :selected_shows, through: :sign_up_form_shows, source: :show

  # Legacy direct slots (for shared_pool mode or migration)
  has_many :sign_up_slots, -> { order(:position) }, dependent: :destroy
  has_many :sign_up_form_holdouts, dependent: :destroy
  has_many :sign_up_registrations, through: :sign_up_slots

  # Questions use polymorphic questionable association
  has_many :questions, as: :questionable, dependent: :destroy
  accepts_nested_attributes_for :questions, reject_if: :all_blank, allow_destroy: true

  # Rich text for instructions
  has_rich_text :instruction_text
  has_rich_text :success_text

  # Sync instance when show changes for single_event forms
  after_save :sync_single_event_instance_show, if: :saved_change_to_show_id?

  validates :name, presence: true
  validates :slots_per_registration, numericality: { greater_than: 0 }, allow_nil: true
  validates :scope, presence: true, inclusion: { in: %w[single_event repeated shared_pool] }
  validates :event_matching, inclusion: { in: %w[all event_types manual] }, allow_nil: true
  validates :slot_generation_mode, inclusion: { in: %w[numbered time_based named simple_capacity open_list] }, allow_nil: true
  validates :slot_selection_mode, inclusion: { in: %w[choose_slot auto_assign admin_assigns] }, allow_nil: true
  validates :url_slug, uniqueness: { scope: :production_id }, allow_blank: true
  validates :short_code, uniqueness: true, allow_blank: true
  validates :queue_limit, numericality: { greater_than: 0 }, allow_nil: true

  # Default values
  attribute :scope, default: "single_event"
  attribute :event_matching, default: "all"
  attribute :slot_generation_mode, default: "numbered"
  attribute :slot_count, default: 10
  attribute :slot_prefix, default: "Slot"
  attribute :slot_capacity, default: 1
  attribute :slot_interval_minutes, default: 5
  attribute :registrations_per_person, default: 1
  attribute :slot_selection_mode, default: "choose_slot"
  attribute :allow_edit, default: true
  attribute :allow_cancel, default: true
  attribute :edit_cutoff_hours, default: 24
  attribute :cancel_cutoff_hours, default: 2
  attribute :show_registrations, default: false
  attribute :schedule_mode, default: "relative"
  attribute :opens_days_before, default: 7
  attribute :closes_hours_before, default: 2
  attribute :queue_carryover, default: false
  attribute :slot_hold_enabled, default: true
  attribute :slot_hold_seconds, default: 30

  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :open, -> { where("opens_at IS NULL OR opens_at <= ?", Time.current) }
  scope :not_closed, -> { where("closes_at IS NULL OR closes_at > ?", Time.current) }
  scope :available, -> { active.open.not_closed }
  scope :repeated, -> { where(scope: "repeated") }
  scope :single_event, -> { where(scope: "single_event") }
  scope :shared_pool, -> { where(scope: "shared_pool") }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :not_archived, -> { where(archived_at: nil) }

  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current, active: false)
  end

  def unarchive!
    update!(archived_at: nil)
  end

  # Custom setter for slot_names that accepts newline-separated text or array
  def slot_names=(value)
    if value.is_a?(String)
      # Split by newlines and strip whitespace, remove blanks
      names = value.split("\n").map(&:strip).reject(&:blank?)
      super(names)
    else
      super(value)
    end
  end

  # Get the status service for this form - provides unified status/timing info
  # This is the ONLY way to get status information - no inline queries allowed
  def status_service
    @status_service ||= SignUpFormStatusService.new(self)
  end

  # Delegate to status service for the canonical status
  def current_status
    status_service.status
  end

  # Convenience methods that delegate to status service
  def accepting_registrations?
    current_status[:accepting_registrations]
  end

  # Scope helpers
  def single_event?
    scope == "single_event"
  end

  def repeated?
    scope == "repeated"
  end

  def shared_pool?
    scope == "shared_pool"
  end

  # Slot selection mode helpers
  def admin_assigns?
    slot_selection_mode == "admin_assigns"
  end

  def auto_assign?
    slot_selection_mode == "auto_assign"
  end

  def choose_slot?
    slot_selection_mode == "choose_slot"
  end

  # Event matching
  def matches_event?(show)
    case event_matching
    when "all"
      true
    when "event_types"
      return true if event_type_filter.blank?
      event_type_filter.include?(show.event_type)
    when "manual"
      sign_up_form_shows.exists?(show_id: show.id)
    else
      false
    end
  end

  # Get all shows that match this form's event criteria
  def matching_shows
    return Show.none unless repeated?

    base_scope = production.shows.where(canceled: false).where("date_and_time > ?", Time.current)

    case event_matching
    when "all"
      base_scope
    when "event_types"
      return base_scope if event_type_filter.blank?
      base_scope.where(event_type: event_type_filter)
    when "manual"
      base_scope.where(id: sign_up_form_shows.select(:show_id))
    else
      Show.none
    end
  end

  # Create an instance for a specific show
  def create_instance_for_show!(show)
    SlotManagementService.new(self).create_instance_for_show!(show)
  end

  # Calculate dates based on show time
  def calculate_opens_at(show)
    # Immediate mode: opens_at is nil (open now)
    return nil if schedule_mode == "immediate"
    return nil unless schedule_mode == "relative" && opens_days_before.present?
    show.date_and_time - opens_days_before.days
  end

  def calculate_closes_at(show)
    # Immediate mode defaults to event_start
    if schedule_mode == "immediate"
      return show.date_and_time
    end
    return nil unless schedule_mode == "relative"

    case closes_mode
    when "event_start"
      # Close exactly when the event starts
      show.date_and_time
    when "custom"
      # Calculate based on offset value, unit, and before/after
      offset_seconds = case closes_offset_unit
      when "minutes" then closes_offset_value.minutes
      when "hours" then closes_offset_value.hours
      when "days" then closes_offset_value.days
      else closes_offset_value.hours
      end
      # Note: closes_before_after is stored but we use negative offset for "before"
      # For backwards compatibility, if closes_hours_before is set, use that
      if closes_offset_value.present? && closes_offset_value > 0
        show.date_and_time - offset_seconds
      elsif closes_hours_before.present?
        show.date_and_time - closes_hours_before.hours
      else
        show.date_and_time
      end
    when "never"
      # Never auto-close
      nil
    else
      # Fallback to legacy behavior
      return nil unless closes_hours_before.present?
      show.date_and_time - closes_hours_before.hours
    end
  end

  def calculate_edit_cutoff_at(show)
    return nil unless edit_cutoff_hours.present?
    closes_at = calculate_closes_at(show) || show.date_and_time
    closes_at - edit_cutoff_hours.hours
  end

  # Apply holdout rules to an instance's slots
  def apply_holdouts_to_instance!(instance)
    instance.sign_up_slots.update_all(is_held: false, held_reason: nil)

    sign_up_form_holdouts.each do |holdout|
      apply_holdout_to_slots(holdout, instance.sign_up_slots)
    end
  end

  # URL helpers
  def public_url_path
    return nil unless url_slug.present?
    "/p/#{production.public_key}/sign-ups/#{url_slug}"
  end

  def generate_url_slug!
    return if url_slug.present?
    base_slug = name.parameterize
    slug = base_slug
    counter = 1

    while SignUpForm.where(production_id: production_id, url_slug: slug).where.not(id: id).exists?
      slug = "#{base_slug}-#{counter}"
      counter += 1
    end

    update!(url_slug: slug)
  end

  def generate_short_code!
    return if short_code.present?

    loop do
      code = SecureRandom.alphanumeric(5).upcase
      unless SignUpForm.exists?(short_code: code)
        update!(short_code: code)
        break
      end
    end
  end

  def short_url_path
    return nil unless short_code.present?
    "/s/#{short_code}"
  end

  # Get the appropriate instance or form for a show
  def instance_for_show(show)
    if repeated?
      sign_up_form_instances.find_by(show: show)
    else
      self # For single_event or shared_pool, use the form directly
    end
  end

  # All upcoming instances for repeated forms
  def upcoming_instances
    sign_up_form_instances.upcoming.includes(:show)
  end

  # Available instances that are currently open
  def open_instances
    sign_up_form_instances.open_status.includes(:show)
  end

  def available_slots
    sign_up_slots.where(is_held: false).left_joins(:sign_up_registrations)
                 .where("sign_up_registrations.id IS NULL OR sign_up_registrations.status = 'cancelled'")
                 .or(sign_up_slots.where(is_held: false)
                 .joins(:sign_up_registrations)
                 .group("sign_up_slots.id")
                 .having("COUNT(sign_up_registrations.id) < sign_up_slots.capacity"))
  end

  def filled_slots_count
    sign_up_slots.joins(:sign_up_registrations)
                 .where.not(sign_up_registrations: { status: "cancelled" })
                 .count
  end

  def total_capacity
    sign_up_slots.where(is_held: false).sum(:capacity)
  end

  # Apply holdout rules to all slots (for shared_pool or legacy forms)
  def apply_holdouts!
    sign_up_slots.update_all(is_held: false, held_reason: nil)

    sign_up_form_holdouts.each do |holdout|
      apply_holdout_to_slots(holdout, sign_up_slots)
    end
  end

  private

  def sync_single_event_instance_show
    return unless single_event?
    return unless show_id.present?

    # For single_event forms, update the instance's show to match the form's show
    instance = sign_up_form_instances.first
    return unless instance

    # Update instance show and recalculate timings
    service = SlotManagementService.new(self)
    instance.update!(
      show_id: show_id,
      opens_at: service.send(:calculate_opens_at, show),
      closes_at: service.send(:calculate_closes_at, show),
      edit_cutoff_at: service.send(:calculate_edit_cutoff_at, show),
      status: "initializing"
    )

    # Run status job to set correct status
    UpdateSignUpStatusesJob.perform_later
  end

  def apply_holdout_to_slots(holdout, slots)
    ordered_slots = slots.order(:position)
    case holdout.holdout_type
    when "first_n"
      ordered_slots.limit(holdout.holdout_value).update_all(is_held: true, held_reason: holdout.reason)
    when "last_n"
      ordered_slots.reverse_order.limit(holdout.holdout_value).update_all(is_held: true, held_reason: holdout.reason)
    when "every_n"
      ordered_slots.where("(position % ?) = 0", holdout.holdout_value).update_all(is_held: true, held_reason: holdout.reason)
    end
  end
end

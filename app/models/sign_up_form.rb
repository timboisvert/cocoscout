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

  validates :name, presence: true
  validates :slots_per_registration, numericality: { greater_than: 0 }, allow_nil: true
  validates :scope, presence: true, inclusion: { in: %w[single_event per_event shared_pool] }
  validates :event_matching, inclusion: { in: %w[all event_types manual] }, allow_nil: true
  validates :slot_generation_mode, inclusion: { in: %w[numbered time_based named simple_capacity open_list] }, allow_nil: true
  validates :url_slug, uniqueness: { scope: :production_id }, allow_blank: true
  validates :short_code, uniqueness: true, allow_blank: true

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
  attribute :schedule_mode, default: "relative"
  attribute :opens_days_before, default: 7
  attribute :closes_hours_before, default: 2

  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :open, -> { where("opens_at IS NULL OR opens_at <= ?", Time.current) }
  scope :not_closed, -> { where("closes_at IS NULL OR closes_at > ?", Time.current) }
  scope :available, -> { active.open.not_closed }
  scope :per_event, -> { where(scope: "per_event") }
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

  def open?
    return false unless active?
    return false if opens_at.present? && opens_at > Time.current
    return false if closes_at.present? && closes_at <= Time.current
    true
  end

  # Returns a user-friendly status for display
  # Possible values: :paused, :scheduled, :accepting, :closed
  def registration_status
    return :paused unless active?
    return :scheduled if opens_at.present? && opens_at > Time.current
    return :closed if closes_at.present? && closes_at <= Time.current
    :accepting
  end

  def registration_status_label
    case registration_status
    when :paused then "Paused"
    when :scheduled then "Opens #{opens_at.strftime('%b %-d')}"
    when :closed then "Closed"
    when :accepting then "Accepting Sign-ups"
    end
  end

  def registration_status_color
    case registration_status
    when :paused then "gray"
    when :scheduled then "yellow"
    when :closed then "gray"
    when :accepting then "green"
    end
  end

  # Scope helpers
  def single_event?
    scope == "single_event"
  end

  def per_event?
    scope == "per_event"
  end

  def shared_pool?
    scope == "shared_pool"
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
    return Show.none unless per_event?

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
    return nil unless per_event? && matches_event?(show)
    return sign_up_form_instances.find_by(show: show) if sign_up_form_instances.exists?(show: show)

    instance = sign_up_form_instances.create!(
      show: show,
      opens_at: calculate_opens_at(show),
      closes_at: calculate_closes_at(show),
      edit_cutoff_at: calculate_edit_cutoff_at(show),
      status: "scheduled"
    )

    instance.generate_slots_from_template!
    instance
  end

  # Calculate dates based on show time
  def calculate_opens_at(show)
    return nil unless schedule_mode == "relative" && opens_days_before.present?
    show.date_and_time - opens_days_before.days
  end

  def calculate_closes_at(show)
    return nil unless schedule_mode == "relative" && closes_hours_before.present?
    show.date_and_time - closes_hours_before.hours
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
    if per_event?
      sign_up_form_instances.find_by(show: show)
    else
      self # For single_event or shared_pool, use the form directly
    end
  end

  # All upcoming instances for per-event forms
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

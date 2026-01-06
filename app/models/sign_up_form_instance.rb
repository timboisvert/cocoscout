# frozen_string_literal: true

class SignUpFormInstance < ApplicationRecord
  belongs_to :sign_up_form
  belongs_to :show

  has_many :sign_up_slots, dependent: :destroy
  has_many :sign_up_registrations, through: :sign_up_slots

  validates :status, presence: true, inclusion: { in: %w[scheduled open closed cancelled] }
  validates :show_id, uniqueness: { scope: :sign_up_form_id, message: "already has an instance for this form" }

  scope :scheduled, -> { where(status: "scheduled") }
  scope :open_status, -> { where(status: "open") }
  scope :closed, -> { where(status: "closed") }
  scope :cancelled, -> { where(status: "cancelled") }
  scope :active, -> { where(status: %w[scheduled open]) }
  scope :upcoming, -> { joins(:show).where("shows.date_and_time > ?", Time.current).order("shows.date_and_time ASC") }

  delegate :production, to: :sign_up_form
  delegate :name, :instruction_text, :success_text, :questions, to: :sign_up_form
  delegate :registrations_per_person, :slot_selection_mode, :require_login, to: :sign_up_form
  delegate :allow_edit, :allow_cancel, :edit_cutoff_hours, :cancel_cutoff_hours, to: :sign_up_form

  # Status helpers
  def scheduled?
    status == "scheduled"
  end

  def open?
    return false unless status == "open"
    return false if opens_at.present? && opens_at > Time.current
    return false if closes_at.present? && closes_at <= Time.current
    true
  end

  def closed?
    status == "closed" || (closes_at.present? && closes_at <= Time.current)
  end

  def cancelled?
    status == "cancelled"
  end

  # Derived status based on current time
  def current_status
    return "cancelled" if cancelled?
    return "closed" if closed?
    return "open" if opens_at.present? && opens_at <= Time.current && (closes_at.nil? || closes_at > Time.current)
    return "scheduled" if opens_at.present? && opens_at > Time.current
    status
  end

  # Time-based checks
  def opens_soon?
    opens_at.present? && opens_at > Time.current && opens_at <= 24.hours.from_now
  end

  def closes_soon?
    closes_at.present? && closes_at > Time.current && closes_at <= 2.hours.from_now
  end

  def past_edit_cutoff?
    return false unless edit_cutoff_at.present?
    Time.current >= edit_cutoff_at
  end

  def past_cancel_cutoff?
    return false unless cancel_cutoff_at.present?
    cancel_cutoff_at = closes_at - cancel_cutoff_hours.hours if closes_at.present?
    return false unless cancel_cutoff_at.present?
    Time.current >= cancel_cutoff_at
  end

  def can_edit?
    allow_edit && !past_edit_cutoff? && !closed? && !cancelled?
  end

  def can_cancel?
    allow_cancel && !past_cancel_cutoff? && !closed? && !cancelled?
  end

  # Check if registrations are allowed for this instance
  def accepts_registrations?
    return false if cancelled?
    return false if show.canceled?
    return false if closed?
    open?
  end

  # Check if the event is still happening (not cancelled/deleted)
  def event_active?
    !cancelled? && !show.canceled?
  end

  # Slot availability
  def available_slots
    sign_up_slots.available
  end

  def full?
    available_slots.none?
  end

  def spots_remaining
    sign_up_slots.sum { |slot| slot.spots_remaining }
  end

  def total_capacity
    sign_up_slots.where(is_held: false).sum(:capacity)
  end

  def registration_count
    sign_up_registrations.active.count
  end

  # Generate slots from template
  def generate_slots_from_template!
    return if sign_up_slots.any? # Don't regenerate if slots exist

    form = sign_up_form
    slots_to_create = []

    case form.slot_generation_mode
    when "numbered"
      form.slot_count.times do |i|
        slots_to_create << {
          position: i + 1,
          name: "#{form.slot_prefix} #{i + 1}",
          capacity: form.slot_capacity
        }
      end

    when "time_based"
      return unless form.slot_start_time.present? && form.slot_interval_minutes.present?

      start_time = Time.parse(form.slot_start_time)
      form.slot_count.times do |i|
        slot_time = start_time + (i * form.slot_interval_minutes.minutes)
        slots_to_create << {
          position: i + 1,
          name: slot_time.strftime("%l:%M %p").strip,
          capacity: form.slot_capacity
        }
      end

    when "named"
      return unless form.slot_names.present?

      form.slot_names.each_with_index do |name, i|
        slots_to_create << {
          position: i + 1,
          name: name,
          capacity: form.slot_capacity
        }
      end

    when "simple_capacity"
      # Single slot with total capacity
      slots_to_create << {
        position: 1,
        name: nil,
        capacity: form.slot_count # slot_count acts as total capacity here
      }
    end

    slots_to_create.each do |attrs|
      sign_up_slots.create!(attrs.merge(sign_up_form_id: sign_up_form_id))
    end

    # Apply any holdout rules if method exists
    sign_up_form.apply_holdouts_to_instance!(self) if sign_up_form.respond_to?(:apply_holdouts_to_instance!)
  end

  # Update status based on current time
  def update_status!
    new_status = if cancelled?
      "cancelled"
    elsif closes_at.present? && closes_at <= Time.current
      "closed"
    elsif opens_at.present? && opens_at <= Time.current
      "open"
    else
      "scheduled"
    end

    update!(status: new_status) if status != new_status
  end

  # Display helpers
  def display_name
    "#{sign_up_form.name} - #{show.name_with_date}"
  end

  def status_badge_class
    case current_status
    when "open" then "bg-green-100 text-green-800"
    when "scheduled" then "bg-yellow-100 text-yellow-800"
    when "closed" then "bg-gray-100 text-gray-800"
    when "cancelled" then "bg-red-100 text-red-800"
    else "bg-gray-100 text-gray-800"
    end
  end
end

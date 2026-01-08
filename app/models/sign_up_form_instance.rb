# frozen_string_literal: true

class SignUpFormInstance < ApplicationRecord
  belongs_to :sign_up_form
  belongs_to :show, optional: true  # Optional for shared_pool forms

  has_many :sign_up_slots, dependent: :destroy
  has_many :sign_up_registrations, through: :sign_up_slots

  # Queued registrations (for admin_assigns mode) - registrations not yet assigned to a slot
  has_many :queued_registrations, -> { queued.order(:position) },
           class_name: "SignUpRegistration",
           foreign_key: :sign_up_form_instance_id,
           dependent: :destroy

  validates :status, presence: true, inclusion: { in: %w[initializing updating scheduled open closed cancelled] }
  validates :show_id, uniqueness: { scope: :sign_up_form_id, message: "already has an instance for this form", allow_nil: true }

  scope :initializing, -> { where(status: "initializing") }
  scope :updating, -> { where(status: "updating") }
  scope :scheduled, -> { where(status: "scheduled") }
  scope :open_status, -> { where(status: "open") }
  scope :closed, -> { where(status: "closed") }
  scope :cancelled, -> { where(status: "cancelled") }
  scope :active, -> { where(status: %w[initializing updating scheduled open]) }
  scope :needs_status_update, -> { where(status: %w[initializing updating scheduled open]) }
  scope :upcoming, -> { joins(:show).where("shows.date_and_time > ?", Time.current).order("shows.date_and_time ASC") }

  delegate :production, to: :sign_up_form
  delegate :name, :instruction_text, :success_text, :questions, to: :sign_up_form
  delegate :registrations_per_person, :slot_selection_mode, :require_login, to: :sign_up_form
  delegate :allow_edit, :allow_cancel, :edit_cutoff_hours, :cancel_cutoff_hours, to: :sign_up_form
  delegate :admin_assigns?, :auto_assign?, :choose_slot?, to: :sign_up_form

  # Status helpers
  def initializing?
    status == "initializing"
  end

  def updating?
    status == "updating"
  end

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

  # Derived status based on current time (what the status SHOULD be)
  def calculated_status
    return "cancelled" if cancelled?
    return "closed" if closes_at.present? && closes_at <= Time.current
    return "open" if opens_at.nil? || opens_at <= Time.current
    "scheduled"
  end

  # The status as stored (may be stale until job runs)
  def current_status
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
    allow_edit && !past_edit_cutoff? && !closed? && !cancelled? && !initializing?
  end

  def can_cancel?
    allow_cancel && !past_cancel_cutoff? && !closed? && !cancelled? && !initializing?
  end

  # Check if registrations are allowed for this instance
  # Only accepts when status is "open" - the job manages this
  def accepts_registrations?
    return false if initializing?
    return false if cancelled?
    return false if show.canceled?
    return false if closed?
    status == "open"
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

  def queue_count
    queued_registrations.count
  end

  # Register to queue (for admin_assigns mode)
  def register_to_queue!(person: nil, guest_name: nil, guest_email: nil)
    raise "Must provide person or guest info" if person.nil? && guest_name.blank?

    # Check queue limit if configured
    form = sign_up_form
    if form.queue_limit.present? && queue_count >= form.queue_limit
      raise "Queue is full"
    end

    # Add person to organization if not already a member
    if person.present? && !production.organization.people.include?(person)
      production.organization.people << person
    end

    queue_position = (queued_registrations.maximum(:position) || 0) + 1

    SignUpRegistration.create!(
      sign_up_form_instance: self,
      sign_up_slot: nil,
      person: person,
      guest_name: guest_name,
      guest_email: guest_email,
      position: queue_position,
      status: "queued",
      registered_at: Time.current
    )
  end

  # Generate slots from template
  def generate_slots_from_template!
    SlotManagementService.new(sign_up_form).generate_slots_for_instance!(self)
  end

  # Display helpers
  def display_name
    "#{sign_up_form.name} - #{show.name_with_date}"
  end

  def status_badge_class
    case current_status
    when "initializing" then "bg-blue-100 text-blue-800"
    when "open" then "bg-green-100 text-green-800"
    when "scheduled" then "bg-yellow-100 text-yellow-800"
    when "closed" then "bg-gray-100 text-gray-800"
    when "cancelled" then "bg-red-100 text-red-800"
    else "bg-gray-100 text-gray-800"
    end
  end

  def status_label
    case current_status
    when "initializing" then "Initializing..."
    when "open" then "Open"
    when "scheduled" then "Scheduled"
    when "closed" then "Closed"
    when "cancelled" then "Cancelled"
    else status.titleize
    end
  end
end

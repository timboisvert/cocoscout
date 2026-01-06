# frozen_string_literal: true

class SignUpSlot < ApplicationRecord
  belongs_to :sign_up_form
  belongs_to :sign_up_form_instance, optional: true

  has_many :sign_up_registrations, -> { order(:position) }, dependent: :destroy
  has_many :people, through: :sign_up_registrations

  validates :position, presence: true, numericality: { greater_than: 0 }
  validates :capacity, numericality: { greater_than: 0 }

  scope :available, -> { where(is_held: false) }
  scope :held, -> { where(is_held: true) }
  scope :for_instance, ->(instance) { where(sign_up_form_instance: instance) }
  scope :direct, -> { where(sign_up_form_instance: nil) }
  scope :with_capacity, -> {
    available.left_joins(:sign_up_registrations)
             .where("sign_up_registrations.id IS NULL OR sign_up_registrations.status = 'cancelled'")
             .or(available.joins(:sign_up_registrations)
             .group("sign_up_slots.id")
             .having("COUNT(CASE WHEN sign_up_registrations.status != 'cancelled' THEN 1 END) < sign_up_slots.capacity"))
  }

  def display_name
    name.presence || "Slot #{position}"
  end

  def available?
    return false if is_held?
    active_registrations_count < capacity
  end

  def active_registrations_count
    sign_up_registrations.where.not(status: "cancelled").count
  end

  def spots_remaining
    [ capacity - active_registrations_count, 0 ].max
  end

  def full?
    active_registrations_count >= capacity
  end

  # Register a person or guest for this slot
  def register!(person: nil, guest_name: nil, guest_email: nil)
    raise "Slot is held" if is_held?
    raise "Slot is full" if full?
    raise "Must provide person or guest info" if person.nil? && guest_name.blank?

    next_position = (sign_up_registrations.maximum(:position) || 0) + 1

    sign_up_registrations.create!(
      person: person,
      guest_name: guest_name,
      guest_email: guest_email,
      position: next_position,
      status: "confirmed",
      registered_at: Time.current
    )
  end

  def hold!(reason: nil)
    update!(is_held: true, held_reason: reason)
  end

  def release!
    update!(is_held: false, held_reason: nil)
  end
end

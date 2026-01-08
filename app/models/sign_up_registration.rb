# frozen_string_literal: true

class SignUpRegistration < ApplicationRecord
  belongs_to :sign_up_slot
  belongs_to :person, optional: true

  # TODO: When adding custom questions to sign-up forms, create a migration to add
  # respondable_id and respondable_type columns to answers table for polymorphic association
  # has_many :answers, as: :respondable, dependent: :destroy

  validates :position, presence: true, numericality: { greater_than: 0 }
  validates :status, presence: true, inclusion: { in: %w[confirmed waitlisted cancelled] }
  validates :registered_at, presence: true
  validates :person, presence: true, unless: :guest?
  validates :guest_name, presence: true, if: :guest?
  validate :person_or_guest_required
  validate :unique_person_per_slot, if: :person_id?

  scope :confirmed, -> { where(status: "confirmed") }
  scope :waitlisted, -> { where(status: "waitlisted") }
  scope :cancelled, -> { where(status: "cancelled") }
  scope :active, -> { where.not(status: "cancelled") }

  delegate :sign_up_form, to: :sign_up_slot

  def guest?
    person_id.blank? && guest_name.present?
  end

  def display_name
    return person.name if person.present?
    guest_name
  end

  def display_email
    return person.email if person.present?
    guest_email
  end

  def display_initials
    return person.initials if person.present?
    return "" if guest_name.blank?

    names = guest_name.split
    if names.length >= 2
      "#{names.first[0]}#{names.last[0]}".upcase
    else
      guest_name[0..1].upcase
    end
  end

  def cancel!
    update!(status: "cancelled", cancelled_at: Time.current)
  end

  def confirmed?
    status == "confirmed"
  end

  def waitlisted?
    status == "waitlisted"
  end

  def cancelled?
    status == "cancelled"
  end

  private

  def person_or_guest_required
    return if person_id.present? || guest_name.present?
    errors.add(:base, "Must have either a person or guest name")
  end

  def unique_person_per_slot
    return unless person_id.present?
    existing = SignUpRegistration.where(sign_up_slot_id: sign_up_slot_id, person_id: person_id)
                                 .where.not(status: "cancelled")
                                 .where.not(id: id)
    if existing.exists?
      errors.add(:person, "is already registered for this slot")
    end
  end
end

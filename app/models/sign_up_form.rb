# frozen_string_literal: true

class SignUpForm < ApplicationRecord
  belongs_to :production
  belongs_to :show, optional: true

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
  validates :slots_per_registration, numericality: { greater_than: 0 }

  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :open, -> { where("opens_at IS NULL OR opens_at <= ?", Time.current) }
  scope :not_closed, -> { where("closes_at IS NULL OR closes_at > ?", Time.current) }
  scope :available, -> { active.open.not_closed }

  def open?
    return false unless active?
    return false if opens_at.present? && opens_at > Time.current
    return false if closes_at.present? && closes_at <= Time.current
    true
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

  # Apply holdout rules to all slots
  def apply_holdouts!
    sign_up_slots.update_all(is_held: false, held_reason: nil)

    sign_up_form_holdouts.each do |holdout|
      apply_holdout(holdout)
    end
  end

  private

  def apply_holdout(holdout)
    slots = sign_up_slots.order(:position)
    case holdout.holdout_type
    when "first_n"
      slots.limit(holdout.holdout_value).update_all(is_held: true, held_reason: holdout.reason)
    when "last_n"
      slots.reverse_order.limit(holdout.holdout_value).update_all(is_held: true, held_reason: holdout.reason)
    when "every_n"
      slots.where("(position % ?) = 0", holdout.holdout_value).update_all(is_held: true, held_reason: holdout.reason)
    end
  end
end

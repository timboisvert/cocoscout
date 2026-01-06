# frozen_string_literal: true

class SignUpFormHoldout < ApplicationRecord
  belongs_to :sign_up_form

  HOLDOUT_TYPES = %w[first_n last_n every_n].freeze

  validates :holdout_type, presence: true, inclusion: { in: HOLDOUT_TYPES }
  validates :holdout_value, presence: true, numericality: { greater_than: 0 }
  validates :holdout_type, uniqueness: { scope: :sign_up_form_id }

  after_save :apply_to_slots
  after_destroy :reset_slots

  def description
    case holdout_type
    when "first_n"
      "Reserve first #{holdout_value} slot#{'s' if holdout_value > 1}"
    when "last_n"
      "Reserve last #{holdout_value} slot#{'s' if holdout_value > 1}"
    when "every_n"
      "Reserve every #{ordinalize(holdout_value)} slot"
    else
      "Unknown holdout type"
    end
  end

  private

  def apply_to_slots
    sign_up_form.apply_holdouts!
  end

  def reset_slots
    sign_up_form.apply_holdouts!
  end

  def ordinalize(n)
    if (11..13).include?(n % 100)
      "#{n}th"
    else
      case n % 10
      when 1 then "#{n}st"
      when 2 then "#{n}nd"
      when 3 then "#{n}rd"
      else "#{n}th"
      end
    end
  end
end

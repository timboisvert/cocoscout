# frozen_string_literal: true

class AdvanceRecovery < ApplicationRecord
  belongs_to :person_advance
  belongs_to :show_payout_line_item

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :person_advance_id, uniqueness: { scope: :show_payout_line_item_id }

  delegate :person, to: :person_advance
  delegate :show, to: :show_payout_line_item
end

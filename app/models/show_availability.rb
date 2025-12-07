# frozen_string_literal: true

class ShowAvailability < ApplicationRecord
  belongs_to :available_entity, polymorphic: true
  belongs_to :show

  enum :status, {
    unset: 0,
    available: 1,
    unavailable: 2
  }, default: :unset

  validates :available_entity_id, uniqueness: { scope: %i[show_id available_entity_type] }
end

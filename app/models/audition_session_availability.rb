# frozen_string_literal: true

class AuditionSessionAvailability < ApplicationRecord
  belongs_to :available_entity, polymorphic: true
  belongs_to :audition_session

  enum :status, {
    unset: 0,
    available: 1,
    unavailable: 2
  }, default: :unset

  validates :available_entity_id, uniqueness: { scope: %i[audition_session_id available_entity_type] }
end

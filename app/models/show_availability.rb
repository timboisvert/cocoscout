class ShowAvailability < ApplicationRecord
  belongs_to :person
  belongs_to :show

  enum :status, {
    unset: 0,
    available: 1,
    unavailable: 2
  }, default: :unset

  validates :person_id, uniqueness: { scope: :show_id }
end

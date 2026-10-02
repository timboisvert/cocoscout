# frozen_string_literal: true

# A date picked by hand for a production's ticketing (event_matching "manual").
class ProductionTicketingShow < ApplicationRecord
  belongs_to :production_ticketing
  belongs_to :show

  validates :show_id, uniqueness: { scope: :production_ticketing_id }
end

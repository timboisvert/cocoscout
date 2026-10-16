# frozen_string_literal: true

# One show differing from what its production (or contract) says it needs:
# needed false is "not this show" for a service it would otherwise get; needed
# true adds one just for this show, or changes how many people it takes. Made
# from the show's panel on Scheduling or its Settings page's Services tab.
class ShowServiceChange < ApplicationRecord
  belongs_to :show
  belongs_to :house_service

  validates :house_service_id, uniqueness: { scope: :show_id }
  validates :people_count, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 20 }
end

# frozen_string_literal: true

module ProductionsHelper
  # Where the Tickets tab sits on Production Settings (manage/productions/edit).
  # A production booked by a contract has fewer tabs (no Agreement, Public
  # Listing or Pay), so its Tickets tab comes earlier.
  def production_tickets_tab(production)
    production.type_third_party? ? 4 : 7
  end
end

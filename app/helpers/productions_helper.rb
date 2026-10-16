# frozen_string_literal: true

module ProductionsHelper
  # Where the Tickets tab sits on Production Settings (manage/productions/edit).
  # A production booked by a contract has fewer tabs (no Agreement, Public
  # Listing or Pay), so its Tickets tab comes earlier.
  def production_tickets_tab(production)
    production.type_third_party? ? 4 : 7
  end

  # Its Services tab (Pro, managers), right after Tickets.
  def production_services_tab(production)
    production_tickets_tab(production) + 1
  end

  # A show's Settings page: its Services tab sits after Tickets (see the
  # edit_tabs list in manage/shows/edit).
  SHOW_SERVICES_TAB = 6
  def show_services_tab
    SHOW_SERVICES_TAB
  end
end

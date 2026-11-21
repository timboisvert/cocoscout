# frozen_string_literal: true

module ProductionsHelper
  # Production Settings' tabs (manage/productions/edit), in order: the one
  # list the tab strip, the phone's section picker, the panels, and every
  # link to a tab go by. Casting sits left of the Pro tabs and Public Listing
  # right of them, just left of Danger Zone (Tim, 2026-11-18). A production
  # booked by a contract has no Casting, Agreement, Pay or Public Listing.
  PRODUCTION_TAB_LABELS = {
    basic: "Basic Information", visual_assets: "Visual Assets", documents: "Documents", team: "Production Team",
    casting: "Casting", agreement: "Agreement", pay: "Pay", tickets: "Tickets", services: "Services",
    public_listing: "Public Listing", danger_zone: "Danger Zone"
  }.freeze
  # The headings the sections sit under in the side list and the phone's
  # sheet (SectionNavHelper#section_groups). The Danger Zone stands apart.
  PRODUCTION_TAB_GROUPS = {
    basic: "Details", visual_assets: "Details", documents: "Details", team: "People", casting: "People",
    agreement: "Business", pay: "Business", tickets: "Business", services: "Business", public_listing: "Public"
  }.freeze

  def production_edit_tabs(production, user = Current.user)
    org = production.organization
    tabs = %i[basic visual_assets documents team]
    tabs << :casting if production.castable?
    tabs += %i[agreement pay] unless production.type_third_party?
    tabs << :tickets
    tabs << :services if org.services_available_to?(user)
    tabs << :public_listing unless production.type_third_party?
    tabs << :danger_zone if user&.superadmin? || org.manageable_by?(user)
    tabs
  end

  # A tab's index, for ?tab= and #tab- links.
  def production_edit_tab(production, key)
    production_edit_tabs(production).index(key) || 0
  end

  def production_tickets_tab(production)
    production_edit_tab(production, :tickets)
  end

  def production_services_tab(production)
    production_edit_tab(production, :services)
  end

  def production_casting_tab(production)
    production_edit_tab(production, :casting)
  end

  # A show's Settings page: its Services tab sits after Tickets (see the
  # edit_tabs list in manage/shows/edit).
  SHOW_SERVICES_TAB = 6
  def show_services_tab
    SHOW_SERVICES_TAB
  end
end

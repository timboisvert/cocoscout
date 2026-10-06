# frozen_string_literal: true

module Manage
  # Giving tickets away from a show's page (TicketComps): one person at a
  # time — name, email, how many, which ticket type — and they get their
  # tickets. The form is the Comps modal on the show's page (Tim,
  # 2026-10-06). (A pasted list can come back if a theater asks for it.)
  class TicketCompsController < Manage::TicketingBaseController
    before_action :set_listing

    # The old Give tickets page: the form is a modal on the show's page now.
    def new
      redirect_to manage_ticket_listing_path(@listing, anchor: "guests")
    end

    def create
      tier = @tiers.find { |t| t.id == params[:tier_id].to_i }
      guest = TicketComps::Guest.new(name: params[:name].to_s.squish, email: params[:email].to_s.strip.downcase.presence,
                                     tier: tier, quantity: params[:quantity].to_i)
      order = TicketComps.give!(@listing, [ guest ], by: Current.user, note: params[:note], email_them: params[:email_them] == "1").sole
      redirect_to manage_ticket_listing_path(@listing, anchor: "guests"),
                  notice: "Gave #{helpers.pluralize(order.tickets.size, 'ticket')} to #{guest.name}. They're on the guest list."
    rescue TicketComps::Error => e
      redirect_to manage_ticket_listing_path(@listing, anchor: "guests"), alert: e.message
    end

    private

    # Scoped to the current org: a bare find here would reach another org's show.
    def set_listing
      @listing = Current.organization.ticket_listings.find(params[:id])
      @tiers = @listing.ticket_tiers.active.to_a
    end
  end
end

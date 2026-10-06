# frozen_string_literal: true

module Manage
  # Giving tickets away from a show's page (TicketComps): one person at a
  # time — name, email, how many, which ticket type — and they get their
  # tickets. (A pasted list can come back if a theater asks for it.)
  class TicketCompsController < Manage::TicketingBaseController
    before_action :set_listing

    def new
      @tier_id = params[:tier_id].presence&.to_i || (@tiers.find { |t| t.price_cents.zero? } || @tiers.first)&.id
      @note = params[:note]
    end

    def create
      tier = @tiers.find { |t| t.id == params[:tier_id].to_i }
      guest = TicketComps::Guest.new(name: params[:name].to_s.squish, email: params[:email].to_s.strip.downcase.presence,
                                     tier: tier, quantity: params[:quantity].to_i)
      order = TicketComps.give!(@listing, [ guest ], by: Current.user, note: params[:note], email_them: params[:email_them] == "1").sole
      # Back here for the next guest; the show page lists them all.
      redirect_to manage_new_ticket_listing_comps_path(@listing, tier_id: tier&.id, note: params[:note].presence),
                  notice: "Gave #{helpers.pluralize(order.tickets.size, 'ticket')} to #{guest.name}. They're on the guest list; add the next person below."
    rescue TicketComps::Error => e
      @name, @email, @quantity = params[:name], params[:email], params[:quantity]
      @tier_id = tier&.id
      @note = params[:note]
      @email_them = params[:email_them] == "1"
      flash.now[:alert] = e.message
      render :new, status: :unprocessable_content
    end

    private

    # Scoped to the current org: a bare find here would reach another org's show.
    def set_listing
      @listing = Current.organization.ticket_listings.find(params[:id])
      @tiers = @listing.ticket_tiers.active.to_a
    end
  end
end

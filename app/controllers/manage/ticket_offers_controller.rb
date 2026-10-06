# frozen_string_literal: true

module Manage
  # Deals on another show (TicketOffer): "buying Boylesque? Add tonight's Laugh
  # Along Live for $5 off." The list, with how often each was shown and
  # taken. Making and changing one is the TicketOfferWizardController.
  class TicketOffersController < Manage::TicketingBaseController
    before_action :set_offer, only: %i[destroy]

    def index
      @offers = Current.organization.ticket_offers.includes(:trigger_listing, :trigger_production, :target_production, target_tier: :ticket_listing)
                       .order(created_at: :desc).to_a
      @taken = Ticket.where(ticket_offer_id: @offers.map(&:id), status: Ticket::SOLD_STATUSES).group(:ticket_offer_id).count
    end

    # A deal somebody took is switched off, so its tickets keep it; one
    # nobody took is deleted.
    def destroy
      name = @offer.name
      if @offer.tickets.exists?
        @offer.update_columns(active: false, updated_at: Time.current)
        redirect_to manage_ticket_offers_path, notice: "#{name} is off. Tickets bought with it keep their price."
      else
        @offer.destroy!
        redirect_to manage_ticket_offers_path, notice: "#{name} deleted."
      end
    end

    private

    # Scoped to the org: a bare find here would reach another theater's deal.
    def set_offer
      @offer = Current.organization.ticket_offers.find(params[:id])
    end
  end
end

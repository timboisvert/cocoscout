# frozen_string_literal: true

module Manage
  # Deals on another show (TicketOffer): "buying Boylesque? Add tonight's Laugh
  # Along Live for $5 off." The list, with how often each was shown and
  # taken, and an editor.
  class TicketOffersController < Manage::TicketingBaseController
    before_action :set_offer, only: %i[edit update destroy]

    def index
      @offers = Current.organization.ticket_offers.includes(:trigger_listing, :trigger_production, :target_production, target_tier: :ticket_listing)
                       .order(created_at: :desc).to_a
      @taken = Ticket.where(ticket_offer_id: @offers.map(&:id), status: Ticket::SOLD_STATUSES).group(:ticket_offer_id).count
    end

    def new
      @offer = Current.organization.ticket_offers.new(trigger_scope: "production", target_scope: "listing", deal_kind: "amount_off")
    end

    def create
      @offer = Current.organization.ticket_offers.new(offer_params)
      if @offer.save
        redirect_to manage_ticket_offers_path, notice: "Saved #{@offer.name}#{' and on' if @offer.active?}."
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit; end

    def update
      if @offer.update(offer_params)
        redirect_to manage_ticket_offers_path, notice: "Saved #{@offer.name}."
      else
        render :edit, status: :unprocessable_content
      end
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

    # Money typed as dollars; ids only ever the organization's own (the model
    # validates that too).
    def offer_params
      permitted = params.require(:ticket_offer).permit(:name, :trigger_scope, :trigger_listing_id, :trigger_production_id,
                                                       :target_scope, :target_tier_id, :target_production_id, :target_tier_name,
                                                       :deal_kind, :amount, :percent, :price, :max_per_order, :starts_at, :ends_at,
                                                       :active, :max_uses, :after_purchase_days)
      permitted[:amount_cents] = dollars_to_cents(permitted.delete(:amount))
      permitted[:price_cents] = dollars_to_cents(permitted.delete(:price))
      %i[percent max_per_order starts_at ends_at max_uses trigger_listing_id trigger_production_id target_tier_id target_production_id target_tier_name].each do |key|
        permitted[key] = permitted[key].presence if permitted.key?(key)
      end
      permitted
    end

    def dollars_to_cents(text)
      cleaned = text.to_s.delete("$,").strip
      cleaned.empty? ? nil : (BigDecimal(cleaned) * 100).round.to_i
    rescue ArgumentError
      raise ActionController::BadRequest, "Amounts must be numbers"
    end
  end
end

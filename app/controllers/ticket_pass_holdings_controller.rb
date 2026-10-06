# frozen_string_literal: true

# A credit pass's own page (/tickets/my-pass/<token>, from the pass email):
# credits left, the covered dates with seats, and "use a credit" on each.
# Using one makes that show's tickets at once (TicketPassCredits.use!). The
# token is the key, like an order's.
class TicketPassHoldingsController < ApplicationController
  include TicketingEmbeddable

  allow_unauthenticated_access
  skip_forgery_protection only: :use

  before_action :set_holding

  def show
    @listings = @holding.usable? ? TicketPassCredits.usable_listings(@holding) : []
    @used = @holding.tickets.where(status: Ticket::SOLD_STATUSES).includes(:ticket_order, ticket_listing: :show).order(:created_at).to_a
  end

  def use
    listing = @holding.organization.ticket_listings.find(params[:listing_id])
    order = TicketPassCredits.use!(@holding, listing: listing, people: params[:people] || 1)
    redirect_to tickets_order_path(token: order.token, **embed_params)
  rescue TicketPassCredits::Error => e
    redirect_to tickets_pass_holding_path(token: @holding.token, **embed_params), alert: e.message
  end

  private

  def set_holding
    @holding = TicketPassHolding.includes(:organization, ticket_pass: { coverages: :production }).find_by!(token: params[:token].to_s)
    raise ActiveRecord::RecordNotFound if @holding.status == "pending"

    @pass = @holding.ticket_pass
    @organization = @holding.organization
    @ticketing_profile = TicketingProfile.for(@organization)
  end
end

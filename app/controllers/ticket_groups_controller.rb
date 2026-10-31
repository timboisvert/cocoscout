# frozen_string_literal: true

# A group leader's page (advanced ticketing plan §3, /tickets/group/:token):
# the seats held, the invoice and how to pay it, the names of the people
# coming, and once paid, the tickets. No sign-in; the token is the key.
class TicketGroupsController < ApplicationController
  include TicketingEmbeddable

  allow_unauthenticated_access
  skip_forgery_protection only: :names
  before_action :set_booking

  def show
    @invoice = @booking.invoice
    @document = @invoice&.document
    @ticketing_profile = TicketingProfile.for(@booking.organization)
  end

  def names
    Ticketing::GroupSales.name!(@booking, params[:names])
    redirect_to tickets_group_path(token: @booking.token, **embed_params), notice: "Names saved."
  end

  private

  def set_booking
    @booking = TicketGroupBooking.includes(:invoice, :ticket_order, ticket_listing: [ :organization, :production, { show: :location } ]).find_by!(token: params[:token].to_s)
    @listing = @booking.ticket_listing
  end
end

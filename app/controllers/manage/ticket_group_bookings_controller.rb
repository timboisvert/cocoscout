# frozen_string_literal: true

module Manage
  # Group sales for one date (advanced ticketing plan §3): the blocks held
  # and ticketed, a form to book one, and a booking's page with its invoice,
  # names and the two hand controls (issue tickets early, release the seats).
  class TicketGroupBookingsController < Manage::TicketingBaseController
    before_action :set_listing
    before_action :set_booking, only: %i[show issue release names]

    def index
      @bookings = @listing.group_bookings.includes(:invoice, :ticket_tier, :ticket_order).order(Arel.sql("CASE status WHEN 'booked' THEN 0 WHEN 'ticketed' THEN 1 ELSE 2 END"), :created_at).to_a
      @live = @bookings.select(&:live?)
    end

    def new
      @booking = @listing.group_bookings.new(seat_count: 20, comp_count: 2, due_on: Date.current + 14, release_on: default_release_on)
      load_tiers
    end

    def create
      attrs = booking_params
      tier = @listing.ticket_tiers.active.find_by(id: attrs.delete(:ticket_tier_id))
      attrs[:ticket_tier] = tier
      attrs[:price_cents] = attrs.key?(:price) ? (attrs.delete(:price).to_s.delete("$,").to_f * 100).round : tier&.price_cents
      @booking = Ticketing::GroupSales.book!(@listing, attrs, by: Current.user)
      redirect_to manage_ticket_listing_group_path(@listing, @booking), notice: "#{helpers.pluralize(@booking.seats, 'seat')} held for #{@booking.name}. The invoice and their group page went to #{@booking.contact_email}."
    rescue Ticketing::GroupSales::Error => e
      @booking = @listing.group_bookings.new(attrs.except(:ticket_tier).merge(ticket_tier: tier))
      load_tiers
      flash.now[:alert] = e.message
      render :new, status: :unprocessable_entity
    end

    def show
      @invoice = @booking.invoice
      @document = @invoice&.document
    end

    def issue
      Ticketing::GroupSales.ticket!(@booking, by: Current.user)
      redirect_to manage_ticket_listing_group_path(@listing, @booking), notice: "Tickets issued to #{@booking.name}#{@booking.paid? ? '' : '; the invoice stays open until it is paid'}."
    rescue Ticketing::GroupSales::Error => e
      redirect_to manage_ticket_listing_group_path(@listing, @booking), alert: e.message
    end

    def release
      Ticketing::GroupSales.release!(@booking, canceled: true, by: Current.user)
      redirect_to manage_ticket_listing_groups_path(@listing), notice: "#{@booking.name}'s seats are back on sale and the invoice is cancelled."
    end

    def names
      Ticketing::GroupSales.name!(@booking, params[:names])
      redirect_to manage_ticket_listing_group_path(@listing, @booking), notice: "Names saved."
    end

    private

    def set_listing
      @listing = Current.organization.ticket_listings.includes(:production, show: :location).find(params[:id])
    end

    def set_booking
      @booking = @listing.group_bookings.find_by!(token: params[:token].to_s)
    end

    def load_tiers
      @tiers = @listing.ticket_tiers.active.reject(&:bundle?)
    end

    # A week before the show, or the due date when that's later, never past
    # the show.
    def default_release_on
      showday = @listing.show.date_and_time.to_date
      [ [ showday - 7, Date.current + 14 ].max, showday ].min
    end

    def booking_params
      params.require(:ticket_group_booking).permit(:name, :contact_name, :contact_email, :contact_phone, :seat_count, :comp_count, :ticket_tier_id, :price, :due_on, :release_on, :notes).to_h.symbolize_keys
    end
  end
end

# frozen_string_literal: true

# The public box office at cocoscout.com/t — no sign-in. A theater's page of
# upcoming shows, a production's dates, and each show's ticket page.
#
# Only theaters with ticketing switched on are public. A signed-in superadmin
# can preview one that isn't yet (with a banner saying so).
class TicketsController < ApplicationController
  allow_unauthenticated_access
  layout "ticketing"

  before_action :set_box_office, except: :ticket

  def box_office
    @productions = selling_listings.map(&:production).uniq.sort_by(&:name)
    @production_filter = @productions.find { |p| p.id.to_s == params[:production].to_s }
    @listings = selling_listings.select { |l| @production_filter.nil? || l.production_id == @production_filter.id }
  end

  def production
    @production = @organization.productions.find_by(id: params[:production].to_s.to_i)
    raise ActiveRecord::RecordNotFound unless @production

    @listings = selling_listings.select { |l| l.production_id == @production.id }
  end

  def event
    @listing = @organization.ticket_listings.find_by(slug: params[:event])
    raise ActiveRecord::RecordNotFound unless @listing

    # A draft's page is only for a superadmin checking it before it goes on sale.
    if @listing.status == "draft"
      raise ActiveRecord::RecordNotFound unless superadmin_viewer?

      @preview = true
    end

    @code = params[:code].to_s.strip.upcase.presence
    @tiers = @listing.ticket_tiers.active.select(&:selling?).reject { |t| t.hidden? && t.unlock_code != @code }
    @inventory = @listing.inventory
    @tax = TaxCalculator.for_ticket(@listing, @tiers.first, 10_000) if @tiers.any?
  end

  # What a phone camera opens from a ticket's QR code: the ticket itself.
  def ticket
    @ticket = Ticket.includes(ticket_order: { ticket_listing: [ :organization, { show: :location } ] }).find_by!(code: params[:code])
    @listing = @ticket.ticket_listing
    @ticketing_profile = TicketingProfile.for(@listing.organization)
  end

  private

  def set_box_office
    @ticketing_profile = TicketingProfile.find_by(slug: params[:org].to_s.downcase)
    raise ActiveRecord::RecordNotFound unless @ticketing_profile

    @preview = !@ticketing_profile.enabled?
    raise ActiveRecord::RecordNotFound if @preview && !superadmin_viewer?

    @organization = @ticketing_profile.organization
  end

  # Upcoming shows that are on sale or about to be (scheduled, paused,
  # sold out, closed online) — anything the public should see listed.
  def selling_listings
    @selling_listings ||= @organization.ticket_listings
                                       .where(status: %w[on_sale paused closed])
                                       .joins(:show).where(shows: { canceled: false })
                                       .where("shows.date_and_time >= ?", Time.current)
                                       .includes(:production, :ticket_tiers, show: %i[location location_space])
                                       .order("shows.date_and_time").to_a
  end

  def superadmin_viewer?
    authenticated? && Current.user&.superadmin?
  end
end

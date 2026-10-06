# frozen_string_literal: true

# The public box office at cocoscout.com/tickets — no sign-in. A theater's page of
# upcoming shows, a production's dates, and each show's ticket page.
#
# Only theaters with ticketing switched on are public. A signed-in superadmin
# can preview one that isn't yet (with a banner saying so).
class TicketsController < ApplicationController
  include TicketingEmbeddable

  allow_unauthenticated_access

  before_action :set_box_office, except: :ticket

  def box_office
    @productions = selling_listings.map(&:production).uniq.sort_by(&:name)
    @production_filter = @productions.find { |p| p.public_key.present? && p.public_key == params[:production].to_s }
    @listings = selling_listings.select { |l| @production_filter.nil? || l.production_id == @production_filter.id }
    @passes = @production_filter ? [] : selling_passes
  end

  # /tickets/<org>/<slug>: a date's ticket page, or — when the slug is a
  # production's public key — the production's page with all its dates.
  def event
    @listing = @organization.ticket_listings.find_by(slug: params[:event])
    return production(@organization.productions.find_by(public_key: params[:event].to_s.downcase)) unless @listing

    # A draft's page is for the organization's managers (and superadmins) checking it before it goes on sale.
    if @listing.status == "draft"
      raise ActiveRecord::RecordNotFound unless preview_viewer?(@organization)

      @preview = true
    end

    check_code(@listing)
    @tiers = @listing.ticket_tiers.active.select(&:selling?).reject { |t| t.hidden? && t.unlock_code != @code }
    @inventory = @listing.inventory
    @tax = TaxCalculator.for_ticket(@listing, @tiers.first, 10_000) if @tiers.any?
    @passes = selling_passes.select do |pass|
      pass.credit_kind? ? pass.coverages.any? { |coverage| coverage.production_id == @listing.production_id } : pass.rows.any? { |row| row.ticket_listing_id == @listing.id }
    end
  end

  # What a phone camera opens from a ticket's QR code: the ticket itself.
  def ticket
    @ticket = Ticket.includes(ticket_order: { ticket_listing: [ :organization, { show: :location } ] }).find_by!(code: params[:code])
    @listing = @ticket.ticket_listing
    @ticketing_profile = TicketingProfile.for(@listing.organization)
  end

  private

  # The production's page: its dates as chips, and the chosen date's tickets
  # (?date= a date's slug, a day like 2026-10-17, or oct-17 as a short link
  # names it; else the first date on sale).
  def production(production)
    raise ActiveRecord::RecordNotFound unless production

    @production = production
    @listings = selling_listings.select { |l| l.production_id == @production.id }
    wanted = params[:date].to_s.downcase
    @listing = @listings.find { |l| l.slug == wanted || l.show.date_and_time.to_date.iso8601 == wanted || ShortLink.date_suffix(l.show) == wanted } ||
               @listings.find { |l| l.selling? && !l.inventory.sold_out? } || @listings.first
    check_code(@listing)
    if @listing
      @tiers = @listing.ticket_tiers.active.select(&:selling?).reject { |t| t.hidden? && t.unlock_code != @code }
      @inventory = @listing.inventory
      @tax = TaxCalculator.for_ticket(@listing, @tiers.first, 10_000) if @tiers.any?
    end
    render :production
  end

  # A code typed on the page is checked right there: a discount for this
  # show, or a hidden ticket type's code. One that doesn't work isn't
  # applied, and the page says so (checkout checks again on its own).
  def check_code(listing)
    @code = params[:code].to_s.strip.upcase.presence
    return if @code.nil? || listing.nil?
    return if TicketCheckout.find_discount(listing, @code) || listing.ticket_tiers.active.any? { |t| t.hidden? && t.unlock_code == @code }

    @code_error = "That code doesn't work for this show."
    @code = nil
  end

  def set_box_office
    @ticketing_profile, moved = TicketingProfile.at_address(params[:org])
    raise ActiveRecord::RecordNotFound unless @ticketing_profile
    # An address the theater used before: send people to its current one.
    if moved
      return redirect_to(request.fullpath.sub("/#{params[:org]}", "/#{@ticketing_profile.slug}"), status: :moved_permanently)
    end

    @preview = !@ticketing_profile.enabled?
    raise ActiveRecord::RecordNotFound if @preview && !preview_viewer?(@ticketing_profile.organization)

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

  # Passes buyers can get right now (TicketPass), soonest first.
  def selling_passes
    @selling_passes ||= @organization.ticket_passes.on_sale.includes(:coverages).to_a
                                     .select { |pass| pass.credit_kind? ? pass.selling_credits? : pass.selling? }
                                     .sort_by { |pass| pass.rows.first&.ticket_listing&.starts_at || Time.current }
  end

  # Who may see a closed box office or a draft page: the organization's own
  # managers, and superadmins.
  def preview_viewer?(organization)
    authenticated? && (Current.user&.superadmin? || organization&.manageable_by?(Current.user))
  end
end

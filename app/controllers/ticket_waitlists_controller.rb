# frozen_string_literal: true

# The waitlist, buyer's side (advanced ticketing plan §7b): joining from a
# sold-out date's page, and a place on the list at its own token address,
# where the person can leave it. No sign-in; the token is the key.
class TicketWaitlistsController < ApplicationController
  include TicketingEmbeddable

  allow_unauthenticated_access
  skip_forgery_protection only: %i[create destroy]

  def create
    if params[:website].present?
      Rails.logger.warn("[TicketWaitlists] honeypot tripped ip=#{request.remote_ip}")
      return redirect_to(tickets_event_path(org: params[:org], event: params[:event], **embed_params))
    end

    profile, = TicketingProfile.at_address(params[:org])
    listing = profile && profile.organization.ticket_listings.find_by(slug: params[:event])
    raise ActiveRecord::RecordNotFound unless listing && profile.enabled?

    entry = Ticketing::Waitlist.join!(listing, name: params[:name], email: params[:email], phone: params[:phone], quantity: params[:quantity], preference: params[:preference])
    redirect_to tickets_waitlist_path(token: entry.token, **embed_params), notice: "You're on the list. We emailed #{entry.email} to say so."
  rescue Ticketing::Waitlist::Error => e
    redirect_to tickets_event_path(org: params[:org], event: params[:event], **embed_params), alert: e.message
  end

  def show
    @entry = TicketWaitlistEntry.includes(ticket_listing: [ :organization, { show: :location } ]).find_by!(token: params[:token].to_s)
    @listing = @entry.ticket_listing
    @ticketing_profile = TicketingProfile.for(@listing.organization)
    @ahead = @listing.waitlist_entries.waiting.where("position < ?", @entry.position).count if @entry.waiting?
  end

  def destroy
    entry = TicketWaitlistEntry.find_by!(token: params[:token].to_s)
    Ticketing::Waitlist.leave!(entry)
    redirect_to tickets_waitlist_path(token: entry.token, **embed_params), notice: "You've left the list."
  end
end

# frozen_string_literal: true

module Manage
  # A production's short links: its one code (cocoscout.com/t/K7M2P, kept
  # forever) and the named links a manager makes to see which poster or post
  # sells. Every link is found through the current organization's production.
  class ShortLinksController < Manage::TicketingBaseController
    before_action :set_production

    def index
      @canonical = ShortLink.canonical_for!(@production)
      @links = @production.short_links.named.live.order(:created_at, :id).to_a
      @dates = Current.organization.ticket_listings.where(production: @production).joins(:show)
                      .where("shows.date_and_time >= ?", Time.current).includes(:show).order("shows.date_and_time").to_a
      @codes = @production.ticket_discount_codes.order(:code).to_a
    end

    def create
      query = { "date" => params[:date].to_s.presence, "code" => params[:code].to_s.strip.upcase.presence }.compact
      link = @production.short_links.new(kind: "named", label: params[:label], query: query,
                                         organization: Current.organization, created_by: Current.user)
      if link.save
        redirect_to manage_production_ticketing_links_path(@production), notice: "#{link.label} is cocoscout.com#{link.short_path}."
      else
        redirect_to manage_production_ticketing_links_path(@production), alert: "Give the link a name, like Poster or Instagram bio."
      end
    end

    # Archiving stops the link; the code is never reissued.
    def destroy
      link = @production.short_links.named.find(params[:id])
      link.update!(archived_at: Time.current)
      redirect_to manage_production_ticketing_links_path(@production), notice: "#{link.label} no longer works."
    end

    private

    def set_production
      @production = Current.organization.productions.find(params[:production_id])
    end
  end
end

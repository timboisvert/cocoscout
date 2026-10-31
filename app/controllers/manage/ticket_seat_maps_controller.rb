# frozen_string_literal: true

module Manage
  # A date's seat map (advanced ticketing plan §1): every seat's state, the
  # holds on it, and the box office's hand: hold seats (house seats, an
  # outside site's block, anything), release a hold. Selling and comping
  # seats from the map arrive with the buyer's map (step 4b).
  class TicketSeatMapsController < Manage::TicketingBaseController
    before_action :set_listing

    def show
      return redirect_to(manage_ticket_listing_path(@listing), alert: "This date sells by count, not by seat.") unless @listing.seated?

      seating = Ticketing::Seating.new(@listing)
      @payload = seating.payload
      respond_to do |format|
        format.html do
          @holds = @listing.seat_holds.live.includes(:hold_seats).order(:created_at).to_a
          @tiers = @listing.ticket_tiers.active.reject(&:bundle?)
          @free = @payload[:sections].sum { |s| s[:seats].count { |x| x[:status] == "free" } }
          @sold = @payload[:sections].sum { |s| s[:seats].count { |x| x[:status] == "sold" } }
          @held = @payload[:sections].sum { |s| s[:seats].count { |x| x[:status] == "held" } }
        end
        format.json { render json: @payload }
      end
    end

    def create_hold
      ids = Array(params[:seat_ids]).map(&:to_i).uniq
      return redirect_to(manage_ticket_listing_seats_path(@listing), alert: "Tap the seats to hold first.") if ids.empty?

      seating = Ticketing::Seating.new(@listing)
      taken = ids.select { |id| seating.taken?(id) || !seating.seats.key?(id) }
      return redirect_to(manage_ticket_listing_seats_path(@listing), alert: "#{helpers.pluralize(taken.size, 'seat')} of those #{taken.size == 1 ? 'is' : 'are'} already sold or held.") if taken.any?

      hold = @listing.seat_holds.new(organization: Current.organization, name: params[:name].to_s.squish.presence || TicketSeatHold::KIND_LABELS[params[:kind].to_s] || "Held",
                                     kind: params[:kind].to_s.presence_in(TicketSeatHold::KINDS) || "manual", created_by: Current.user,
                                     release_at: (Time.zone.parse(params[:release_at].to_s) rescue nil))
      hold.transaction do
        hold.save!
        ids.each { |id| hold.hold_seats.create!(ticket_listing: @listing, seat_id: id) }
      end
      redirect_to manage_ticket_listing_seats_path(@listing), notice: "#{helpers.pluralize(ids.size, 'seat')} held: #{hold.name}."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to manage_ticket_listing_seats_path(@listing), alert: e.record.errors.full_messages.to_sentence
    end

    def release_hold
      hold = @listing.seat_holds.find(params[:hold_id])
      hold.release!
      WaitlistOfferJob.perform_later(@listing.id) if @listing.waitlist_entries.live.exists?
      redirect_to manage_ticket_listing_seats_path(@listing), notice: "#{hold.name} released: #{helpers.pluralize(hold.hold_seats.size, 'seat')} back on sale."
    end

    private

    def set_listing
      @listing = Current.organization.ticket_listings.includes(:production, show: :location).find(params[:id])
    end
  end
end

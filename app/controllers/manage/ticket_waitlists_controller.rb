# frozen_string_literal: true

module Manage
  # A date's waitlist (advanced ticketing plan §7b): who's waiting and in
  # what order, offers out and how they went, take someone off, offer now by
  # hand, and a note to everyone waiting (seen before it goes).
  class TicketWaitlistsController < Manage::TicketingBaseController
    before_action :set_listing

    def show
      @entries = @listing.waitlist_entries.order(:position, :id).includes(:offer_order).to_a
      @waiting = @entries.select(&:waiting?)
      @offered = @entries.select(&:offered?)
      @done = @entries.reject(&:live?).sort_by(&:updated_at).reverse.first(50)
      show = @listing.show
      @draft = ContentTemplateService.render("ticket_waitlist_note",
                                             { first_name: "{{first_name}}", organization_name: Current.organization.name, show_title: @listing.display_title,
                                               show_date: show.date_and_time.strftime("%A, %B %-d"), message: "" })
    end

    # The edited draft to the ticked people, {{first_name}} filled per person.
    def send_note
      entries = @listing.waitlist_entries.live.where(id: Array(params[:person_ids]).map(&:to_i))
      return redirect_to(manage_ticket_listing_waitlist_path(@listing), alert: "Tick at least one person.") if entries.empty?
      return redirect_to(manage_ticket_listing_waitlist_path(@listing), alert: "Write a subject and a message.") if params[:subject].blank? || params[:body].blank?

      count = Ticketing::Waitlist.send_note!(entries.to_a, subject: params[:subject].to_s.squish, body: params[:body].to_s.strip)
      redirect_to manage_ticket_listing_waitlist_path(@listing), notice: "Sent to #{helpers.pluralize(count, 'person')} on the list."
    end

    # Offer whatever seats are free right now, without waiting for the sweep.
    def offer
      offered = Ticketing::Waitlist.offer_returned_seats!(@listing)
      notice = offered.any? ? "Offered seats to #{offered.map(&:name).to_sentence}; they have 30 minutes." : "No seats are free for anyone waiting right now."
      redirect_to manage_ticket_listing_waitlist_path(@listing), notice: notice
    end

    def destroy
      entry = @listing.waitlist_entries.find_by!(token: params[:entry_id]) # entries go by token (to_param)
      Ticketing::Waitlist.leave!(entry)
      redirect_to manage_ticket_listing_waitlist_path(@listing), notice: "#{entry.name} is off the list."
    end

    private

    def set_listing
      @listing = Current.organization.ticket_listings.includes(:production, show: :location).find(params[:id])
    end
  end
end

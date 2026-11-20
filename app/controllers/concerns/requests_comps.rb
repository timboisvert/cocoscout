# frozen_string_literal: true

# Requesting more comps for one date (CompRequest; Tim, 2026-11-20), from
# where a side issues them: a production team manager on their sales page, a
# contract person on the date's Tickets page on My. Anyone on the side may
# send one, when the comp rules let that side request, and withdraw the one
# waiting.
module RequestsComps
  extend ActiveSupport::Concern

  def request_comps_for(listing, back:)
    side = TicketSalesAccess.comp_side(Current.user, listing)
    return redirect_to(back, alert: "You can't request comps for this date.") unless side && TicketSalesAccess.comp_allowance(Current.user, listing)

    request = CompRequest.request!(listing, side: side, by: Current.user, quantity: params[:quantity], note: params[:note])
    redirect_to back, notice: "Your request for #{CompRequestNotices.more_comps(request.quantity)} has been sent. #{listing.organization.name} has been notified."
  rescue CompRequest::Error => e
    redirect_to back, alert: e.message
  end

  def withdraw_comp_request_for(listing, back:)
    side = TicketSalesAccess.comp_side(Current.user, listing)
    request = side && CompRequest.waiting.find_by(ticket_listing: listing, side: side.to_s)
    return redirect_to(back, alert: "There's no request waiting for this date.") unless request

    request.withdraw!
    redirect_to back, notice: "Your request was withdrawn."
  rescue CompRequest::Error => e
    redirect_to back, alert: e.message
  end

  private

  # What the side's Comps box shows of its requests: the one waiting, else
  # the latest answer.
  def comp_request_for(listing)
    side = TicketSalesAccess.comp_side(Current.user, listing)
    side && CompRequest.latest_for(listing, side)
  end
end

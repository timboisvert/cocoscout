# frozen_string_literal: true

# The comps form (manage/ticket_listings/comps_modal) handled within someone's
# allowance (TicketSalesAccess.comp_allowance): a production team manager on
# their sales page, a contract person on My Ticket Sales. One person at a
# time, never more than what's left to them. Mirrors the manager's own
# Manage::TicketCompsController#create.
module GivesComps
  extend ActiveSupport::Concern

  def give_comp_within_allowance(listing, allowance, back:)
    unless allowance && (allowance[:left].nil? || allowance[:left].positive?)
      return redirect_to(back, alert: "You can't give comps for this date.")
    end

    quantity = params[:quantity].to_i
    if allowance[:left] && quantity > allowance[:left]
      return redirect_to(back, alert: "You can give #{helpers.pluralize(allowance[:left], 'more comp')} for this date.")
    end

    tier = listing.ticket_tiers.active.find { |t| t.id == params[:tier_id].to_i }
    email = params[:email].to_s.strip.downcase.presence
    email_them = params[:email_them] == "1"
    if email_them && email.blank?
      return redirect_to(back, alert: "Add their email to send their tickets, or switch off Email them their tickets.")
    end

    guest = TicketComps::Guest.new(name: params[:name].to_s.squish, email: email, tier: tier, quantity: quantity)
    order = TicketComps.give!(listing, [ guest ], by: Current.user, note: params[:note], email_them: email_them).sole
    redirect_to back, notice: "Gave #{helpers.pluralize(order.tickets.size, 'ticket')} to #{guest.name}. They're on the list."
  rescue TicketComps::Error => e
    redirect_to back, alert: e.message
  end
end

# frozen_string_literal: true

# The comps form (manage/ticket_listings/comps_modal) handled within someone's
# allowance (TicketSalesAccess.comp_allowance): a production team manager on
# their sales page, a contract person on My Ticket Sales. One at a
# time, or a pasted list (mode=paste), never more than what's left to them.
# The manager's own Manage::TicketCompsController uses the pasted list with
# no allowance.
module GivesComps
  extend ActiveSupport::Concern

  def give_comp_within_allowance(listing, allowance, back:)
    unless allowance && (allowance[:left].nil? || allowance[:left].positive?)
      return redirect_to(back, alert: "You can't give comps for this date.")
    end
    return give_pasted_comps(listing, back: back, allowance_left: allowance[:left]) if pasting_comps?

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

  # The pasted list's preview, into the open modal (fetched, so no Turbo).
  def preview_comps_within_allowance(listing, allowance)
    return head(:forbidden) unless allowance

    render_comps_preview(listing, allowance_left: allowance[:left])
  end

  private

  def pasting_comps? = params[:mode] == "paste"

  def render_comps_preview(listing, allowance_left: nil)
    render partial: "manage/ticket_listings/comps_preview", locals: { preview: pasted_comps(listing, allowance_left: allowance_left) }
  end

  # Checked again as it's given, the way the preview showed it: every line
  # read and the whole list within the comps, seats and allowance left; then
  # all of it given in one go (TicketComps.give!), or none.
  def give_pasted_comps(listing, back:, allowance_left: nil)
    preview = pasted_comps(listing, allowance_left: allowance_left)
    return redirect_to(back, alert: preview.stopper) unless preview.ready?

    orders = TicketComps.give!(listing, preview.guests, by: Current.user, note: params[:note], email_them: preview.email_them)
    tickets = orders.sum { |o| o.tickets.size }
    redirect_to back, notice: "Gave #{helpers.pluralize(tickets, 'ticket')} to #{helpers.pluralize(orders.size, 'person', plural: 'people')}. They're on the guest list."
  rescue TicketComps::Error => e
    redirect_to back, alert: e.message
  end

  def pasted_comps(listing, allowance_left:)
    tier = listing.ticket_tiers.active.reject(&:bundle?).find { |t| t.id == params[:tier_id].to_i }
    TicketComps.preview(listing, params[:text], tier: tier, email_them: params[:email_them] == "1", allowance_left: allowance_left)
  end
end

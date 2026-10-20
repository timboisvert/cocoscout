# frozen_string_literal: true

# After seats are taken — an online sale, a door sale, comps, a pass used —
# tell the organization, each kind to whoever ticked it in Ticketing settings
# → Notifications, and check the milestones it crossed (sold out, almost sold
# out). Off the request thread, so buying never waits on email.
class TicketingAfterSaleJob < ApplicationJob
  queue_as :default

  # Which notice each way of selling sends (Tim, 2026-10-19: a setting for
  # each of online, door, comp and pass).
  NOTICES = {
    "online" => :sale, "embed" => :sale,
    "door_tap" => :door_sale, "door_card" => :door_sale, "door_cash" => :door_sale,
    "comp" => :comp_issued,
    "pass" => :pass_redeemed, "door_pass" => :pass_redeemed
  }.freeze

  # together: the other orders given in the same go (TicketComps gives one
  # order per guest), so a guest list is one comp email, not one per guest.
  def perform(order_id, together: nil)
    order = TicketOrder.includes(:organization, tickets: :ticket_tier, ticket_listing: :show).find_by(id: order_id)
    return unless order&.paid?

    if (kind = NOTICES[order.channel])
      TicketingNotifier.notify(order.organization, kind, variables: variables(kind, order, together))
    end
    TicketingMilestones.check!(order.ticket_listing)
  end

  private

  def variables(kind, order, together)
    case kind
    when :sale then TicketingNotificationContent.sale(order)
    when :door_sale then TicketingNotificationContent.door_sale(order)
    when :pass_redeemed then TicketingNotificationContent.pass_redeemed(order)
    when :comp_issued
      orders = together.present? ? TicketOrder.includes(:tickets).where(id: together).order(:id).to_a : [ order ]
      TicketingNotificationContent.comps(orders, by: order.issued_by)
    end
  end
end

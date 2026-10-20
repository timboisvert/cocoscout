# frozen_string_literal: true

# After seats are taken — an online sale, comps, a door sale — tell the
# organization: the sale itself, to whoever ticked "Each sale", and any
# milestone it crossed (sold out, almost sold out). Off the request thread,
# so buying never waits on email.
class TicketingAfterSaleJob < ApplicationJob
  queue_as :default

  # Every sale someone paid for: online, on the organization's website, and
  # at the door by tap, scan to pay or cash (Tim, 2026-10-19: "any door
  # purchase"). Comps and passes used at the door take no money, so they
  # stay quiet.
  SALE_CHANNELS = %w[online embed door_tap door_card door_cash].freeze

  def perform(order_id)
    order = TicketOrder.includes(:organization, tickets: :ticket_tier, ticket_listing: :show).find_by(id: order_id)
    return unless order&.paid?

    if SALE_CHANNELS.include?(order.channel)
      TicketingNotifier.notify(order.organization, :sale, variables: TicketingNotificationContent.sale(order))
    end
    TicketingMilestones.check!(order.ticket_listing)
  end
end

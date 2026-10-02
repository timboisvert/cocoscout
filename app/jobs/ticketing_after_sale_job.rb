# frozen_string_literal: true

# After seats are taken — an online sale, comps, a door sale — tell the
# theater: the sale itself (online and website sales only; the door and comps
# are the theater's own doing), and any milestone it crossed (sold out,
# almost sold out). Off the request thread, so buying never waits on email.
class TicketingAfterSaleJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    order = TicketOrder.includes(:organization, tickets: :ticket_tier, ticket_listing: :show).find_by(id: order_id)
    return unless order&.paid?

    if %w[online embed].include?(order.channel)
      TicketingNotifier.notify(order.organization, :sale, variables: TicketingNotificationContent.sale(order))
    end
    TicketingMilestones.check!(order.ticket_listing)
  end
end

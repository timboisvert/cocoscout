# frozen_string_literal: true

# Every few minutes: unpaid checkouts whose ten-minute hold ran out are marked
# expired: ticket orders, and course registrations the same way. Their seats
# already count as free (Ticketing::Inventory and CourseOffering ignore a
# lapsed hold); this keeps the lists honest. A payment that still arrives
# later is handled by TicketOrderSettlement / CourseCheckoutSettlement.
class ExpireTicketHoldsJob < ApplicationJob
  queue_as :default

  def perform
    TicketOrder.stale.update_all(status: "expired", updated_at: Time.current)
    TicketPurchase.stale.update_all(status: "expired", updated_at: Time.current)
    CourseRegistration.stale.update_all(status: "expired", updated_at: Time.current)
  end
end

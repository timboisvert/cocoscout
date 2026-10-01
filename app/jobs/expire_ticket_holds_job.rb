# frozen_string_literal: true

# Every few minutes: unpaid checkouts whose ten-minute hold ran out are marked
# expired. Their seats already count as free (Ticketing::Inventory ignores a
# lapsed hold); this keeps the order list honest. A payment that still
# arrives later is handled by TicketOrderSettlement.
class ExpireTicketHoldsJob < ApplicationJob
  queue_as :default

  def perform
    TicketOrder.stale.update_all(status: "expired", updated_at: Time.current)
  end
end

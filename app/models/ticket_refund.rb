# frozen_string_literal: true

# Money given back to a ticket buyer, for a whole order or some of its
# tickets (see TicketOrderRefund). It records what the buyer got back — the
# tickets' price and tax, plus the fees they paid unless the theater kept
# them — and what that cost the theater's balance: our 50¢ per ticket is
# never kept on a refund, so the theater gives up that much less.
class TicketRefund < ApplicationRecord
  STATUSES = %w[pending succeeded failed].freeze

  belongs_to :organization
  belongs_to :ticket_order
  belongs_to :refunded_by, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :succeeded, -> { where(status: "succeeded") }

  def tickets
    ticket_order.tickets.where(id: ticket_ids)
  end

  def items
    ticket_order.ticket_order_items.where(id: item_ids)
  end
end

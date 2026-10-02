# frozen_string_literal: true

# Tickets moved from one date to another (TicketOrderExchange): which ones,
# the order they left and the one they joined, and the theater's money that
# moved with them. When the new date cost less, the refunded difference is a
# refund on the new order.
class TicketExchange < ApplicationRecord
  belongs_to :organization
  belongs_to :from_order, class_name: "TicketOrder"
  belongs_to :to_order, class_name: "TicketOrder"
  belongs_to :exchanged_by, class_name: "User", optional: true
  belongs_to :ticket_refund, optional: true

  # Why the difference couldn't be refunded, for the manager who just moved
  # them (the failed refund on the new order keeps the record).
  attr_accessor :refund_error
end

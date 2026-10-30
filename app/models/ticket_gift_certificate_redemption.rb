# frozen_string_literal: true

# Money drawn from a gift certificate by one checkout. Held while the buyer
# is paying (the certificate's remaining balance already drawn down, the way
# seats are held), redeemed when the order settles, released when the hold
# runs out. A refund that puts money back on the certificate is a row of its
# own (status refunded, with its TicketRefund).
class TicketGiftCertificateRedemption < ApplicationRecord
  STATUSES = %w[held redeemed released refunded].freeze

  belongs_to :ticket_gift_certificate
  belongs_to :ticket_purchase, optional: true
  belongs_to :ticket_order, optional: true
  belongs_to :ticket_refund, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :held, -> { where(status: "held") }
end

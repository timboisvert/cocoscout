# frozen_string_literal: true

# One thing a gift certificate is good for: every date of a production
# (ticket_listing nil), or one date of it.
class TicketGiftCertificateScope < ApplicationRecord
  belongs_to :ticket_gift_certificate
  belongs_to :production
  belongs_to :ticket_listing, optional: true
end

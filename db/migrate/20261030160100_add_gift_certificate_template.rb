# frozen_string_literal: true

# The email a gift certificate's recipient gets when a manager issues one,
# and the refund emails say where the money went back to ({{refund_where}}:
# the card, the certificate, or both) instead of always "the card".
class AddGiftCertificateTemplate < ActiveRecord::Migration[8.0]
  def up
    TicketingTemplates.ensure!(keys: %w[ticket_gift_certificate_issued])
    TicketingTemplates.ensure!(keys: %w[ticket_order_refunded ticket_event_canceled], overwrite: true)
  end

  def down
    ContentTemplate.where(key: "ticket_gift_certificate_issued").delete_all
  end
end

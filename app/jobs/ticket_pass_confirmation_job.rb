# frozen_string_literal: true

# Sends the buyer of credit passes their passes: each one's page, where they
# use its credits.
class TicketPassConfirmationJob < ApplicationJob
  queue_as :default

  def perform(purchase_id)
    purchase = TicketPurchase.find_by(id: purchase_id)
    holdings = purchase&.ticket_pass_holdings&.select { |holding| holding.status == "active" }
    return if holdings.blank? || holdings.first.holder_email.blank?

    TicketOrderMailer.passes(purchase).deliver_now
  end
end

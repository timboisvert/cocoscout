# frozen_string_literal: true

# Canceling a show that sold tickets: everyone who bought online gets their
# money back — price, tax and fees — and an email the manager has read and
# can edit first (the ticket_event_canceled template). The listing stops
# selling at once; the refunds and emails run in TicketShowCancellationJob.
# The show's money never becomes spendable: the refunds use it up.
class TicketShowCancellation
  Draft = Data.define(:orders, :refund_cents, :subject, :body)

  def self.orders(listing)
    listing.ticket_orders.paid_like.where(money_path: "cocoscout").includes(:tickets).order(:buyer_name)
  end

  # Who gets a refund and what the email says, before anything happens.
  def self.draft(listing)
    orders = orders(listing).to_a
    refund_cents = orders.sum { |order| TicketOrderRefund.quote(order).amount_cents }
    template = ContentTemplateService.find_template("ticket_event_canceled")
    Draft.new(orders: orders, refund_cents: refund_cents,
              subject: template&.subject.to_s, body: TicketOrderMailer.plain_text(template&.body))
  end

  def self.start!(listing, subject:, body:, by:, cancel_show: false)
    listing.update!(status: "canceled")
    listing.show.update!(canceled: true) if cancel_show && !listing.show.canceled
    TicketShowCancellationJob.perform_later(listing.id, subject.to_s, body.to_s, by&.id)
  end
end

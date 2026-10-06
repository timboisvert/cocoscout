# frozen_string_literal: true

# Canceling a show that sold tickets: everyone who bought online gets their
# money back — price, tax and fees — and an email the manager has read and
# can edit first (the ticket_event_canceled template). The listing stops
# selling at once; the refunds and emails run in TicketShowCancellationJob.
# The show's money never becomes spendable: the refunds use it up.
#
# Canceling happens where shows are canceled (Shows & Events): that screen
# shows the ticket buyers and the email, and cancel_shows! does the
# ticketing part for every date being canceled.
class TicketShowCancellation
  Summary = Data.define(:orders, :refund_cents) do
    def any?
      orders.any?
    end
  end

  def self.orders(listing)
    listing.ticket_orders.paid_like.where(money_path: "cocoscout").includes(:tickets).order(:buyer_name)
  end


  # The email every buyer gets, before the manager edits it.
  def self.default_email
    template = ContentTemplateService.find_template("ticket_event_canceled")
    [ template&.subject.to_s, TicketOrderMailer.plain_text(template&.body) ]
  end

  # Who'd be refunded, and how much, if these shows were canceled.
  def self.summary(shows)
    listings = TicketListing.where(show_id: shows.map(&:id)).where.not(status: "canceled").to_a
    found = listings.flat_map { |listing| orders(listing).to_a }
    Summary.new(orders: found, refund_cents: found.sum { |order| TicketOrderRefund.quote(order, reprice: false).amount_cents })
  end

  # The ticketing part of canceling shows: every listing stops selling, and
  # (when the manager chose to) every buyer is refunded and emailed. Returns
  # how many orders are being refunded.
  def self.cancel_shows!(shows, subject:, body:, by:, refund:)
    TicketListing.where(show_id: shows.map(&:id)).where.not(status: "canceled").to_a.sum do |listing|
      count = orders(listing).count
      if count.positive? && refund
        start!(listing, subject: subject, body: body, by: by)
        count
      else
        listing.update!(status: "canceled") if count.zero?
        0
      end
    end
  end

  def self.start!(listing, subject:, body:, by:)
    listing.update!(status: "canceled")
    TicketShowCancellationJob.perform_later(listing.id, subject.to_s, body.to_s, by&.id)
  end
end

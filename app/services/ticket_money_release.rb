# frozen_string_literal: true

# The day after a show, its ticket money becomes the theater's to spend: the
# listing is stamped released (TicketBalance moves its money from "upcoming
# shows" to spendable once the card money has settled), and the books move
# its sales out of "Tickets sold for upcoming shows" into Ticket income,
# tagged with the show and production. Nothing is sent anywhere.
#
# A canceled show is never released — its money refunds its buyers.
class TicketMoneyRelease
  def self.due(at = Time.current)
    TicketListing.joins(:show)
                 .where(released_at: nil)
                 .where.not(status: "canceled")
                 .where(shows: { canceled: false })
                 .where(shows: { date_and_time: ...at.beginning_of_day })
  end

  def self.release!(listing, at: Time.current)
    released = false
    listing.with_lock do
      next if listing.released_at.present? || listing.status == "canceled" || listing.show.canceled

      listing.update!(released_at: at)
      recognize_income!(listing, at.to_date)
      released = true
    end
    if released
      TicketingNotifier.notify(listing.organization, :after_show, variables: TicketingNotificationContent.after_show(listing),
                                                                about: listing, once: true)
    end
    released
  end

  # What's waiting in advance sales for this show — tickets, and products
  # bought with them — becomes income.
  def self.recognize_income!(listing, on)
    organization = listing.organization
    waiting = ->(key) { -JournalLine.where(ledger_account_id: ChartOfAccounts.account(organization, key).id, show_id: listing.show_id).sum(:amount_cents) }
    tickets = waiting.call(:advance_ticket_sales)
    products = waiting.call(:advance_product_sales)
    return if tickets.zero? && products.zero?

    dims = { show: listing.show, production: listing.production }
    LedgerPosting.post!(organization: organization, source: listing, kind: "recognition",
                        entry_date: listing.show.date_and_time.to_date, memo: "Ticket income: #{listing.display_title}",
                        lines: [
                          { account: :advance_ticket_sales, amount_cents: tickets, **dims },
                          { account: :ticket_income, amount_cents: -tickets, **dims },
                          { account: :advance_product_sales, amount_cents: products, **dims },
                          { account: :product_income, amount_cents: -products, **dims }
                        ])
  end

  private_class_method :recognize_income!
end

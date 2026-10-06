# frozen_string_literal: true

# The ticket slice of the theater's CocoScout balance (CocoScoutBalance is
# the whole: tickets, courses and contract money, stage G). Always worked
# out from the cash ledger (OrgCashEntry), never stored:
#
#   upcoming  — sold for shows that haven't happened yet. Not spendable: if a
#               show is canceled, this is what refunds its buyers.
#   settling  — the show has happened; the card money is still reaching
#               Stripe's available balance (about two days after each sale).
#   available — spendable. Payout runs use it before debiting the bank, and
#               the theater can withdraw it to its bank any time. Money the
#               theater adds from its bank (BalanceTopUp) counts here too.
#
# Spending is recorded where it happens: a payout run's balance_applied_cents
# and BalanceWithdrawal rows. Neither counts once it has failed (or, for a
# withdrawal, been reversed back to us).
class TicketBalance
  SETTLE_AFTER = 2.days
  # A moved order's money leaves its old show (ticket_exchange_out) and joins
  # the new one (ticket_exchange_in), so it's held for the show it's for.
  # pass_sale: a credit pass's money (TicketPassCredits), held until the pass
  # ends; it never joins an order, so the per-show buckets skip it.
  ENTRY_TYPES = %w[ticket_sale ticket_refund ticket_dispute ticket_exchange_out ticket_exchange_in pass_sale pass_refund].freeze
  ORDER_OF_ENTRY = <<~SQL.squish
    LEFT JOIN ticket_refunds r ON e.source_type = 'TicketRefund' AND r.id = e.source_id
    LEFT JOIN ticket_exchanges x ON e.source_type = 'TicketExchange' AND x.id = e.source_id
    JOIN ticket_orders o ON o.id = CASE e.source_type
      WHEN 'TicketOrder' THEN e.source_id
      WHEN 'TicketRefund' THEN r.ticket_order_id
      ELSE CASE e.entry_type WHEN 'ticket_exchange_out' THEN x.from_order_id ELSE x.to_order_id END
    END
  SQL

  Summary = Data.define(:upcoming_cents, :settling_cents, :available_cents, :spent_cents) do
    def total_cents
      upcoming_cents + settling_cents + available_cents
    end

    def any?
      total_cents.positive? || spent_cents.positive?
    end
  end

  def self.summary(organization)
    upcoming, settling, settled = buckets(organization)
    spent = spent_cents(organization)
    Summary.new(upcoming_cents: [ upcoming, 0 ].max, settling_cents: [ settling, 0 ].max,
                available_cents: [ settled + top_ups_cents(organization) - spent, 0 ].max, spent_cents: spent)
  end

  # Spendable money that's been here more than a year (oldest first): what
  # the 12-month rule sends back to the theater's bank.
  def self.aged_cents(organization, now: Time.current)
    recent = recent_settled_cents(organization, since: now - 1.year) +
             BalanceTopUp.succeeded.where(organization_id: organization.id).where(updated_at: (now - 1.year)..).sum(:amount_cents)
    [ available_cents(organization) - recent, 0 ].max
  end

  def self.available_cents(organization)
    summary(organization).available_cents
  end

  # How much more the balance needs to pay `cents` from it. Works from the
  # true balance, not the one floored at zero for display — a dispute or a
  # refund can leave it below zero, and a top-up has to cover that too.
  def self.shortfall_cents(organization, cents)
    _, _, settled = buckets(organization)
    [ cents - (settled + top_ups_cents(organization) - spent_cents(organization)), 0 ].max
  end

  # Ticket money that isn't spendable yet. OrgCashEntry.available_cents keeps
  # it out of reach of every other draw on the org's money.
  def self.held_cents(organization)
    upcoming, settling, = buckets(organization)
    [ upcoming, 0 ].max + [ settling, 0 ].max
  end

  # [upcoming, settling, settled] net cents, from every ticket entry on the
  # org's cash ledger, placed by its order's show and payment date. A refund's
  # or dispute's entry lands in the same bucket as the sale it takes back; a
  # moved order's lands with the show it moved from, or to. (The new order
  # keeps the original payment date, so its money settles on time.)
  def self.buckets(organization)
    sql = <<~SQL.squish
      SELECT
        COALESCE(SUM(e.amount_cents) FILTER (WHERE l.released_at IS NULL), 0),
        COALESCE(SUM(e.amount_cents) FILTER (WHERE l.released_at IS NOT NULL AND o.paid_at > :cutoff), 0),
        COALESCE(SUM(e.amount_cents) FILTER (WHERE l.released_at IS NOT NULL AND o.paid_at <= :cutoff), 0)
      FROM org_cash_entries e
      #{ORDER_OF_ENTRY}
      JOIN ticket_listings l ON l.id = o.ticket_listing_id
      WHERE e.organization_id = :organization_id AND e.entry_type IN (:types)
    SQL
    row = OrgCashEntry.connection.select_rows(
      OrgCashEntry.sanitize_sql([ sql, { organization_id: organization.id, types: ENTRY_TYPES, cutoff: SETTLE_AFTER.ago } ])
    ).first
    upcoming, settling, settled = row.map(&:to_i)
    held_passes, ended_passes = pass_buckets(organization)
    [ upcoming + held_passes, settling, settled + ended_passes ]
  end

  # Credit passes' money: held while the pass runs (its credits are shows
  # still to come), the organization's once it ends.
  def self.pass_buckets(organization)
    sql = <<~SQL.squish
      SELECT
        COALESCE(SUM(e.amount_cents) FILTER (WHERE h.status NOT IN ('ended', 'canceled')), 0),
        COALESCE(SUM(e.amount_cents) FILTER (WHERE h.status IN ('ended', 'canceled')), 0)
      FROM org_cash_entries e
      JOIN ticket_pass_holdings h ON e.source_type = 'TicketPassHolding' AND h.id = e.source_id
      WHERE e.organization_id = :organization_id AND e.entry_type IN ('pass_sale', 'pass_refund')
    SQL
    OrgCashEntry.connection.select_rows(OrgCashEntry.sanitize_sql([ sql, { organization_id: organization.id } ])).first.map(&:to_i)
  end

  # A run claims its share while it's being funded (still a draft for those
  # few seconds), so every run counts except one whose funding failed.
  def self.top_ups_cents(organization)
    BalanceTopUp.succeeded.where(organization_id: organization.id).sum(:amount_cents)
  end

  # Settled, released ticket money from orders paid since a time.
  def self.recent_settled_cents(organization, since:)
    sql = <<~SQL.squish
      SELECT COALESCE(SUM(e.amount_cents), 0)
      FROM org_cash_entries e
      #{ORDER_OF_ENTRY}
      JOIN ticket_listings l ON l.id = o.ticket_listing_id
      WHERE e.organization_id = :organization_id AND e.entry_type IN (:types)
        AND l.released_at IS NOT NULL AND o.paid_at > :since
    SQL
    OrgCashEntry.connection.select_value(
      OrgCashEntry.sanitize_sql([ sql, { organization_id: organization.id, types: ENTRY_TYPES, since: since } ])
    ).to_i
  end

  def self.spent_cents(organization)
    PayoutBatch.where(organization_id: organization.id).where.not(status: "failed").sum(:balance_applied_cents) +
      BalanceWithdrawal.where(organization_id: organization.id).not_failed.sum(:amount_cents)
  end

  private_class_method :buckets, :pass_buckets, :spent_cents, :top_ups_cents
end

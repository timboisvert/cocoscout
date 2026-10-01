# frozen_string_literal: true

# The theater's CocoScout balance: the ticket money CocoScout holds for it
# (course and contract money join in v1.1). Always worked out from the cash
# ledger (OrgCashEntry), never stored:
#
#   upcoming  — sold for shows that haven't happened yet. Not spendable: if a
#               show is canceled, this is what refunds its buyers.
#   settling  — the show has happened; the card money is still reaching
#               Stripe's available balance (about two days after each sale).
#   available — spendable. Payout runs use it before debiting the bank, and
#               the theater can withdraw it to its bank any time.
#
# Spending is recorded where it happens: a payout run's balance_applied_cents
# and BalanceWithdrawal rows. Neither counts once it has failed.
class TicketBalance
  SETTLE_AFTER = 2.days
  ENTRY_TYPES = %w[ticket_sale ticket_refund ticket_dispute].freeze

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
                available_cents: [ settled - spent, 0 ].max, spent_cents: spent)
  end

  def self.available_cents(organization)
    summary(organization).available_cents
  end

  # Ticket money that isn't spendable yet. OrgCashEntry.available_cents keeps
  # it out of reach of every other draw on the org's money.
  def self.held_cents(organization)
    upcoming, settling, = buckets(organization)
    [ upcoming, 0 ].max + [ settling, 0 ].max
  end

  # [upcoming, settling, settled] net cents, from every ticket entry on the
  # org's cash ledger, placed by its order's show and payment date. A refund's
  # or dispute's entry lands in the same bucket as the sale it takes back.
  def self.buckets(organization)
    sql = <<~SQL.squish
      SELECT
        COALESCE(SUM(e.amount_cents) FILTER (WHERE l.released_at IS NULL), 0),
        COALESCE(SUM(e.amount_cents) FILTER (WHERE l.released_at IS NOT NULL AND o.paid_at > :cutoff), 0),
        COALESCE(SUM(e.amount_cents) FILTER (WHERE l.released_at IS NOT NULL AND o.paid_at <= :cutoff), 0)
      FROM org_cash_entries e
      LEFT JOIN ticket_refunds r ON e.source_type = 'TicketRefund' AND r.id = e.source_id
      JOIN ticket_orders o ON o.id = CASE WHEN e.source_type = 'TicketOrder' THEN e.source_id ELSE r.ticket_order_id END
      JOIN ticket_listings l ON l.id = o.ticket_listing_id
      WHERE e.organization_id = :organization_id AND e.entry_type IN (:types)
    SQL
    row = OrgCashEntry.connection.select_rows(
      OrgCashEntry.sanitize_sql([ sql, { organization_id: organization.id, types: ENTRY_TYPES, cutoff: SETTLE_AFTER.ago } ])
    ).first
    row.map(&:to_i)
  end

  # A run claims its share while it's being funded (still a draft for those
  # few seconds), so every run counts except one whose funding failed.
  def self.spent_cents(organization)
    PayoutBatch.where(organization_id: organization.id).where.not(status: "failed").sum(:balance_applied_cents) +
      BalanceWithdrawal.where(organization_id: organization.id).where.not(status: "failed").sum(:amount_cents)
  end

  private_class_method :buckets, :spent_cents
end

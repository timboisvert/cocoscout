# frozen_string_literal: true

# Stage G: one balance for all the money CocoScout holds for a theater.
# Tickets, course registrations and contract payments collected online all
# land in the org's cash ledger (OrgCashEntry); payout runs spend that
# balance first, and the theater withdraws the rest whenever it likes.
# Always worked out from the ledger, never stored:
#
#   upcoming  — ticket money for shows that haven't happened (TicketBalance).
#               Not spendable: it refunds the buyers if a show is canceled.
#   settling  — money still reaching Stripe's available balance: ticket money
#               from shows that just happened, and course or contract money
#               from the last two days.
#   available — everything else in the ledger, less what funded runs still
#               owe their payees and less funding credit (money a run
#               released back, which the next run spends through
#               PayoutFundingCredit, not from here).
#
# Pooling is on for theaters with ticketing switched on. Anyone else keeps
# today's remittance: course and contract money rides the payout run to
# their own Stripe account, and only ticket money (none) is spendable here.
class CocoScoutBalance
  SETTLE_AFTER = TicketBalance::SETTLE_AFTER
  OTHER_CREDITS = %w[course_registration contract_payment].freeze

  Summary = Data.define(:upcoming_cents, :settling_cents, :available_cents, :sources) do
    def total_cents
      upcoming_cents + settling_cents + available_cents
    end

    def any?
      total_cents.positive? || sources.values.any?(&:positive?)
    end
  end

  def self.pooled?(organization)
    organization.ticketing_profile&.enabled? == true
  end

  def self.summary(organization)
    tickets = TicketBalance.summary(organization)
    return Summary.new(upcoming_cents: tickets.upcoming_cents, settling_cents: tickets.settling_cents,
                       available_cents: tickets.available_cents, sources: sources(organization)) unless pooled?(organization)

    Summary.new(upcoming_cents: tickets.upcoming_cents,
                settling_cents: tickets.settling_cents + settling_other_cents(organization),
                available_cents: available_cents(organization), sources: sources(organization))
  end

  # Spendable now: by a payout run, a refund, or a withdrawal.
  def self.available_cents(organization)
    return TicketBalance.available_cents(organization) unless pooled?(organization)

    [ raw_available_cents(organization), 0 ].max
  end

  # The true number, below zero when a dispute or refund took more than was
  # there; a top-up has to cover that too.
  def self.raw_available_cents(organization)
    OrgCashEntry.balance_cents(organization) - OrgCashEntry.committed_cents(organization) -
      held_cents(organization) - PayoutFundingCredit.available_cents(organization)
  end

  def self.shortfall_cents(organization, cents)
    return TicketBalance.shortfall_cents(organization, cents) unless pooled?(organization)

    [ cents - raw_available_cents(organization), 0 ].max
  end

  # In the ledger but not spendable: ticket money waiting on its show or
  # settling, and (once the theater pools) course or contract money from the
  # last two days. A theater that doesn't pool keeps its old reach.
  def self.held_cents(organization)
    held = TicketBalance.held_cents(organization)
    held += settling_other_cents(organization) if pooled?(organization)
    held
  end

  def self.settling_other_cents(organization)
    [ OrgCashEntry.where(organization: organization, entry_type: OTHER_CREDITS).where("occurred_at > ?", SETTLE_AFTER.ago).sum(:amount_cents), 0 ].max
  end

  # Spendable money that's been here more than a year, oldest first: what
  # the 12-month rule sends back to the theater's bank.
  def self.aged_cents(organization, now: Time.current)
    return TicketBalance.aged_cents(organization, now: now) unless pooled?(organization)

    recent = OrgCashEntry.where(organization: organization, entry_type: OTHER_CREDITS + %w[top_up])
                         .where("occurred_at > ?", now - 1.year).sum(:amount_cents) +
             TicketBalance.recent_settled_cents(organization, since: now - 1.year)
    [ available_cents(organization) - recent, 0 ].max
  end

  # Where the money came from and where it went, for the Balance page.
  def self.sources(organization)
    sums = OrgCashEntry.where(organization: organization).group(:entry_type).sum(:amount_cents)
    {
      tickets: TicketBalance::ENTRY_TYPES.sum { |t| sums.fetch(t, 0) },
      courses: sums.fetch("course_registration", 0) + sums.fetch("refund", 0),
      contracts: sums.fetch("contract_payment", 0),
      added: sums.fetch("top_up", 0) + sums.fetch("funding", 0),
      paid_out: -(sums.fetch("transfer", 0) + sums.fetch("transfer_reversal", 0)) - BalanceWithdrawal.where(organization_id: organization.id).where.not(status: "failed").sum(:amount_cents),
      withdrawn: BalanceWithdrawal.where(organization_id: organization.id).where.not(status: "failed").sum(:amount_cents)
    }
  end
end

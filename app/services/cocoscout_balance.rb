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
#   tax set aside — sales tax collected that the organization owes the
#               government (SalesTaxSetAside), kept apart until it marks
#               the period paid. On by default; a setting turns it off.
#   available — everything else in the ledger, less what funded runs still
#               owe their payees and less funding credit (money a run
#               released back, which the next run spends through
#               PayoutFundingCredit, not from here).
#
# Pooling is on for every Pro organization, ticketing or not (Tim,
# 2026-10-25: "incoming payments would all just go into our balance"): the
# balance page is Pro, and every Pro organization can reach it. A non-Pro
# organization (courses only) that has never been Pro keeps the old
# remittance: its course share rides the payout run to its own Stripe account.
# Pooling sticks (organizations.balance_pooled_at): one that leaves Pro keeps
# its one ledger, and LapsedBalanceSweepJob sends its balance to its bank
# each day, since it can no longer open the balance page.
class CocoScoutBalance
  SETTLE_AFTER = TicketBalance::SETTLE_AFTER
  OTHER_CREDITS = %w[course_registration contract_payment].freeze

  Summary = Data.define(:upcoming_cents, :settling_cents, :tax_set_aside_cents, :available_cents, :sources) do
    def total_cents
      upcoming_cents + settling_cents + tax_set_aside_cents + available_cents
    end

    def any?
      total_cents.positive? || sources.values.any?(&:positive?)
    end
  end

  def self.pooled?(organization)
    return true if organization.balance_pooled_at.present?
    return false unless organization.feature_available?(:ticketing) || organization.ticketing_profile&.enabled? == true

    # Stamped the first time it's seen pooling, so pooling outlasts the plan.
    organization.update_column(:balance_pooled_at, Time.current) if organization.persisted?
    true
  end

  def self.summary(organization)
    tickets = TicketBalance.summary(organization)
    tax = SalesTaxSetAside.cents(organization)
    return Summary.new(upcoming_cents: tickets.upcoming_cents, settling_cents: tickets.settling_cents, tax_set_aside_cents: tax,
                       available_cents: available_cents(organization), sources: sources(organization)) unless pooled?(organization)

    Summary.new(upcoming_cents: tickets.upcoming_cents,
                settling_cents: tickets.settling_cents + settling_other_cents(organization), tax_set_aside_cents: tax,
                available_cents: available_cents(organization), sources: sources(organization))
  end

  # Spendable now: by a payout run, a refund, or a withdrawal.
  def self.available_cents(organization)
    return [ TicketBalance.available_cents(organization) - SalesTaxSetAside.cents(organization), 0 ].max unless pooled?(organization)

    [ raw_available_cents(organization), 0 ].max
  end

  # The true number, below zero when a dispute or refund took more than was
  # there; a top-up has to cover that too.
  def self.raw_available_cents(organization)
    OrgCashEntry.balance_cents(organization) - OrgCashEntry.committed_cents(organization) -
      held_cents(organization) - PayoutFundingCredit.available_cents(organization)
  end

  def self.shortfall_cents(organization, cents)
    return TicketBalance.shortfall_cents(organization, cents + SalesTaxSetAside.cents(organization)) unless pooled?(organization)

    [ cents - raw_available_cents(organization), 0 ].max
  end

  # In the ledger but not spendable: ticket money waiting on its show or
  # settling, (once the organization pools) course or contract money from
  # the last two days, and sales tax set aside for the government. An
  # organization that doesn't pool keeps its old reach.
  def self.held_cents(organization)
    held = TicketBalance.held_cents(organization) + SalesTaxSetAside.cents(organization)
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
      paid_out: -(sums.fetch("transfer", 0) + sums.fetch("transfer_reversal", 0)) - BalanceWithdrawal.where(organization_id: organization.id).not_failed.sum(:amount_cents),
      withdrawn: BalanceWithdrawal.where(organization_id: organization.id).not_failed.sum(:amount_cents)
    }
  end
end

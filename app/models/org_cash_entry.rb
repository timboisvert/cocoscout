# frozen_string_literal: true

# A single line in an organization's virtual CASH ledger — the org's share of
# the money sitting in CocoScout's one shared Stripe platform balance.
#
# This is the money-side twin of the app's data multi-tenancy: all orgs' cash
# lives in one Stripe account (like all their rows live in one database), and
# this ledger is what keeps Org A from paying out money that belongs to Org B.
#
# NOT the same thing as PayoutLedgerEntry — that tracks what an org owes each
# payee (a liability). This tracks what CocoScout holds FOR the org (cash).
#
# Sign convention (amount_cents is signed):
#   course_registration → positive  (a student paid; org's net share arrived)
#   contract_payment    → positive  (a contractor/renter paid the org)
#   funding             → positive  (the org's ACH/card funding debit settled)
#   transfer            → negative  (money sent to a payee's Connect account)
#   refund              → negative  (a registration was refunded from the pool)
#   transfer_reversal   → positive  (a sent transfer came back to the pool)
#   opening_balance     → positive  (one-time backfill residue per org)
#   adjustment          → signed    (superadmin correction)
#
# Balances are always derived by summing — never cached. Posts are idempotent
# on (source, entry_type), mirroring PayoutLedgerEntry.
class OrgCashEntry < ApplicationRecord
  ENTRY_TYPES = %w[course_registration contract_payment funding transfer
                   refund transfer_reversal opening_balance adjustment].freeze

  # Namespace for pg_advisory_xact_lock so our (ns, org_id) pairs can't collide
  # with any other advisory-lock user in the app.
  ADVISORY_LOCK_NAMESPACE = 3084 # 0x0C0C

  class InsufficientFunds < StandardError
    attr_reader :available_cents, :requested_cents

    def initialize(available_cents:, requested_cents:)
      @available_cents = available_cents
      @requested_cents = requested_cents
      super("Organization's held balance (#{available_cents}¢) can't cover #{requested_cents}¢")
    end
  end

  belongs_to :organization
  belongs_to :source, polymorphic: true, optional: true

  validates :entry_type, inclusion: { in: ENTRY_TYPES }
  validates :amount_cents, numericality: { only_integer: true }
  validates :currency, presence: true
  validates :occurred_at, presence: true

  # Whether an insufficient balance actually BLOCKS a transfer/refund, or the
  # ledger just records silently. Off by default so the ledger can accrue and
  # be reconciled against the real Stripe balance in production before any
  # payout behavior changes; flipping the env var off again is the kill switch.
  def self.enforcement_enabled?
    ENV["ORG_CASH_ENFORCEMENT"] == "1"
  end

  # Every cent of the platform balance attributable to the org.
  def self.balance_cents(organization)
    where(organization: organization).sum(:amount_cents)
  end

  # Money in the balance that's already spoken for: unpaid items on funded
  # performer/staff runs. Their funding credit is in the ledger, but those
  # transfers WILL go out (enforce: false, pinned to the funding charge), so
  # nothing else may spend that slice in the meantime.
  #
  # `except:` — the item currently drawing, when it's one of these committed
  # items (a funded-run item falling back to an unpinned balance transfer);
  # its own slice is what it's spending, not something else spoken for.
  def self.committed_cents(organization, except: nil)
    scope = PayoutBatchItem.joins(:payout_batch)
                           .where(payout_batches: { organization_id: organization.id,
                                                    funding_status: "succeeded",
                                                    status: %w[funded processing partially_paid] })
                           .where.not(payout_batches: { kind: "course" })
                           .where(status: PayoutBatch::RETRYABLE_ITEM_STATUSES)
    scope = scope.where.not(id: except.id) if except.is_a?(PayoutBatchItem)
    scope.sum(:amount_cents)
  end

  # What the org can actually spend on an unfunded draw (course runs, refunds).
  def self.available_cents(organization, except: nil)
    balance_cents(organization) - committed_cents(organization, except: except)
  end

  # Idempotently record (or restate) the entry for a given source — same
  # contract as PayoutLedgerEntry.post!.
  def self.post!(organization:, entry_type:, amount_cents:, source: nil,
                 description: nil, occurred_at: Time.current, currency: "usd")
    attrs = {
      organization: organization,
      amount_cents: amount_cents,
      description: description,
      occurred_at: occurred_at,
      currency: currency
    }

    if source
      entry = find_or_initialize_by(
        source_type: source.class.polymorphic_name,
        source_id: source.id,
        entry_type: entry_type
      )
      entry.assign_attributes(attrs)
      entry.save!
      entry
    else
      create!(attrs.merge(entry_type: entry_type))
    end
  end

  def self.unpost!(source:, entry_type:)
    return 0 unless source

    where(
      source_type: source.class.polymorphic_name,
      source_id: source.id,
      entry_type: entry_type
    ).delete_all
  end

  # Serialize all balance mutations for one org (cross-org never contends).
  # Transaction-scoped, so the lock releases on commit/rollback — callers must
  # do Stripe network calls OUTSIDE the block.
  def self.with_org_lock(organization)
    transaction do
      connection.execute(
        "SELECT pg_advisory_xact_lock(#{ADVISORY_LOCK_NAMESPACE}, #{organization.id.to_i})"
      )
      yield
    end
  end

  # Reserve money for an outbound draw: under the org lock, check availability
  # and post the negative entry. Callers perform the Stripe call after this
  # returns and unpost! on Stripe failure (reserve-then-transfer).
  #
  # enforce: false is for transfers pinned to a funding charge via
  # source_transaction — Stripe itself guarantees the charge covers them, so
  # they post without an availability check and can never be blocked.
  #
  # A retry of an already-posted source restates the same row, so the amount
  # any prior attempt reserved is credited back before the availability check —
  # a crash between debit and transfer can't wrongly fail the retry.
  def self.debit!(organization:, amount_cents:, source:, entry_type: "transfer",
                  enforce: true, description: nil, occurred_at: Time.current)
    raise ArgumentError, "amount_cents must be positive" unless amount_cents.positive?

    with_org_lock(organization) do
      if enforce && enforcement_enabled?
        already_reserved = source ? where(
          source_type: source.class.polymorphic_name,
          source_id: source.id,
          entry_type: entry_type
        ).sum(:amount_cents) : 0
        available = available_cents(organization, except: source) - already_reserved

        if available < amount_cents
          raise InsufficientFunds.new(available_cents: available, requested_cents: amount_cents)
        end
      end

      post!(
        organization: organization,
        entry_type: entry_type,
        amount_cents: -amount_cents,
        source: source,
        description: description,
        occurred_at: occurred_at
      )
    end
  end
end

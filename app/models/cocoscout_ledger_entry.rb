# frozen_string_literal: true

# CocoScout's own money: every dollar it earned or spent, as a signed ledger
# beside OrgCashEntry (the theaters' share of the same Stripe balance).
# Together the two account for the whole balance, which the daily check
# (PlatformReconciliation) compares with Stripe's.
#
# Rows are posted by CocoScoutLedgerPoster from the record that caused them,
# idempotent per (source, entry_type), and restated when the record changes.
class CocoScoutLedgerEntry < ApplicationRecord
  self.table_name = "cocoscout_ledger_entries"

  # [plain label, group]. Groups: income, cost, bank (money moved between
  # Stripe and CocoScout's own bank), adjustment.
  TYPES = {
    "ticket_fee" => [ "Ticket fees (50¢ a ticket)", :income ],
    "ticket_processing" => [ "Card processing charged on tickets", :income ],
    "ticket_refund" => [ "Fees given back on ticket refunds", :income ],
    "course_fee" => [ "Course fees", :income ],
    "course_refund" => [ "Course fees given back on refunds", :income ],
    "contract_processing" => [ "Card processing passed on to theaters", :income ],
    "subscription" => [ "Pro subscriptions", :income ],
    "usage" => [ "Usage ($3 per performer, $5 per staff)", :income ],
    "other_income" => [ "Other Stripe income", :income ],
    "processing_cost" => [ "Stripe's card processing", :cost ],
    "funding_cost" => [ "Stripe's bank-debit fees we absorb", :cost ],
    "stripe_fee" => [ "Other Stripe fees (Connect, Billing)", :cost ],
    "payout_to_bank" => [ "Sent to CocoScout's bank", :bank ],
    "added_from_bank" => [ "Added from CocoScout's bank", :bank ],
    "opening_difference" => [ "Opening difference", :adjustment ],
    "explained" => [ "Explained by hand", :adjustment ]
  }.freeze

  belongs_to :organization, optional: true
  belongs_to :source, polymorphic: true, optional: true

  validates :entry_type, inclusion: { in: TYPES.keys }
  validates :amount_cents, numericality: { only_integer: true }

  scope :income, -> { where(entry_type: types_in(:income)) }
  scope :costs, -> { where(entry_type: types_in(:cost)) }
  scope :bank, -> { where(entry_type: types_in(:bank)) }

  def self.types_in(group)
    TYPES.select { |_, (_, g)| g == group }.keys
  end

  def self.label(type)
    TYPES.fetch(type, [ type.to_s.humanize ]).first
  end

  def self.balance_cents
    sum(:amount_cents)
  end

  # Idempotently record (or restate) one entry for a source. Zero removes it.
  def self.post!(source:, entry_type:, amount_cents:, occurred_at:, organization: nil, description: nil)
    entry = find_or_initialize_by(source_type: source.class.polymorphic_name, source_id: source.id, entry_type: entry_type)
    if amount_cents.to_i.zero?
      entry.destroy! if entry.persisted?
      return nil
    end

    entry.assign_attributes(amount_cents: amount_cents.to_i, occurred_at: occurred_at, organization: organization, description: description)
    entry.save! if entry.changed?
    entry
  end

  def self.unpost!(source:, entry_types: nil)
    scope = where(source_type: source.class.polymorphic_name, source_id: source.id)
    scope = scope.where(entry_type: entry_types) if entry_types
    scope.destroy_all
  end

  def label
    self.class.label(entry_type)
  end
end

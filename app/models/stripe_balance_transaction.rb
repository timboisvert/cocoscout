# frozen_string_literal: true

# One line of CocoScout's Stripe platform balance, the way Stripe's own
# statement shows it: a charge, a refund, a transfer to a payee or a
# theater, a payout to CocoScout's bank, a Stripe fee. Imported by
# StripeBalanceImport and matched (StripeTransactionMatcher) to the record
# that caused it, so every cent in Stripe is accounted for by something in
# CocoScout, or listed for a superadmin to explain.
#
#   match_status  matched    — tied to its record (or a kind that needs none)
#                 mismatch   — tied to its record, but the amounts disagree
#                 unmatched  — nothing in CocoScout explains it yet
#                 explained  — a superadmin explained it by hand
class StripeBalanceTransaction < ApplicationRecord
  MATCH_STATUSES = %w[matched mismatch unmatched explained].freeze

  # What the line was for, in words.
  CATEGORIES = {
    "ticket_order" => "Ticket sale",
    "course_registration" => "Course registration",
    "contract_payment" => "Contract payment collected",
    "top_up" => "Theater added funds",
    "run_funding" => "Payout run bank debit",
    "billing" => "Pro or usage bill",
    "ticket_refund" => "Ticket refund",
    "course_refund" => "Course refund",
    "payee_transfer" => "Paid to a payee",
    "withdrawal" => "Theater withdrawal",
    "transfer_reversal" => "Transfer came back",
    "dispute" => "Disputed charge",
    "payout_to_bank" => "Sent to CocoScout's bank",
    "added_from_bank" => "Added from CocoScout's bank",
    "stripe_fee" => "Stripe fee",
    "other_income" => "Other Stripe income",
    "unknown" => "Not recognized"
  }.freeze

  belongs_to :organization, optional: true
  belongs_to :matched, polymorphic: true, optional: true
  belongs_to :explained_by, class_name: "User", optional: true

  validates :stripe_id, presence: true, uniqueness: true
  validates :match_status, inclusion: { in: MATCH_STATUSES }
  validates :category, inclusion: { in: CATEGORIES.keys }

  scope :needs_a_look, -> { where(match_status: %w[unmatched mismatch]) }
  scope :newest_first, -> { order(occurred_at: :desc, id: :desc) }

  after_commit -> { CocoScoutLedgerPoster.post_for!(self) }

  # Write (or refresh) the row for one Stripe::BalanceTransaction, its source
  # expanded, and match it.
  def self.import!(stripe)
    row = find_or_initialize_by(stripe_id: stripe.id)
    row.assign_attributes(
      txn_type: stripe.type, reporting_category: stripe["reporting_category"],
      amount_cents: stripe.amount, fee_cents: stripe.fee.to_i, net_cents: stripe.net,
      currency: stripe.currency, status: stripe.status,
      occurred_at: Time.zone.at(stripe.created), available_on: stripe.available_on && Time.zone.at(stripe.available_on).to_date,
      description: stripe.description.to_s.truncate(255).presence,
      source_id: source_id_of(stripe.source), refs: refs_of(stripe.source)
    )
    StripeTransactionMatcher.apply!(row) unless row.match_status == "explained"
    row.save! if row.changed?
    row
  end

  def self.source_id_of(source)
    source.is_a?(String) ? source : source&.id
  end

  # The ids worth matching on, read off the expanded source.
  # Read as a plain hash: the gem raises on fields newer API versions removed.
  def self.refs_of(source)
    return {} unless source.respond_to?(:to_hash)

    hash = source.to_hash.deep_stringify_keys
    refs = {}
    %w[payment_intent charge customer invoice transfer source_transfer].each do |key|
      value = hash[key]
      value = value["id"] if value.is_a?(Hash)
      refs[key] = value if value.is_a?(String) && value.present?
    end
    refs["object"] = hash["object"] if hash["object"].is_a?(String)
    refs
  end

  def category_label
    CATEGORIES.fetch(category, category.to_s.humanize)
  end

  def needs_a_look?
    match_status.in?(%w[unmatched mismatch])
  end

  # A superadmin says what an unmatched line was. It then counts as
  # CocoScout's own money (CocoScoutLedgerPoster posts it as "explained").
  def explain!(note:, by:)
    update!(match_status: "explained", note: note, explained_by: by, explained_at: Time.current)
  end
end

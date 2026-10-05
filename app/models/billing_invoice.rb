# frozen_string_literal: true

# What Stripe billed an organization: its Pro plan, or its monthly usage
# ($3 per performer paid, $5 per staff member scheduled). Mirrored from
# Stripe by BillingInvoiceSync (invoice webhooks plus a nightly sweep), so
# CocoScout knows every bill it sent, and whether it was paid, without
# opening Stripe.
class BillingInvoice < ApplicationRecord
  KINDS = %w[pro usage other].freeze
  STATUSES = %w[draft open paid uncollectible void].freeze

  belongs_to :organization

  validates :stripe_invoice_id, presence: true, uniqueness: true
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }

  scope :paid, -> { where(status: "paid") }
  scope :unpaid, -> { where(status: %w[open uncollectible]) }
  scope :newest_first, -> { order(Arel.sql("COALESCE(period_start, created_at) DESC")) }

  # Not on destroy: a bill that was paid stays in CocoScout's income even if
  # the org is deleted.
  after_commit -> { CocoScoutLedgerPoster.post_for!(self) }, on: %i[create update]

  def label
    case kind
    when "pro" then "Pro plan"
    when "usage" then "Usage"
    else "Other"
    end
  end

  def status_label
    case status
    when "paid" then "Paid"
    when "open" then failed_at.present? ? "Payment failed" : "Due"
    when "uncollectible" then "Couldn't collect"
    when "void" then "Voided"
    else "Draft"
    end
  end

  def failed?
    status == "uncollectible" || (status == "open" && failed_at.present?)
  end
end

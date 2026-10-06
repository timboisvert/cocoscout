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
    when "open"
      if failed_at.present? then "Payment failed"
      elsif collecting? then lands_on ? "Being collected, lands about #{lands_on.strftime('%b %-d')}" : "Being collected"
      else "Due"
      end
    when "uncollectible" then "Couldn't collect"
    when "void" then "Voided"
    else "Draft"
    end
  end

  # The month the bill covers: the middle of its period. A usage period that
  # runs from the 30th to the 30th covers the second month, so a bill whose
  # period starts August 30 is September's.
  def covered_month
    UsageInvoiceCorrection.billed_month(self)
  end

  # What the bill is for: "September 2026 usage", "Pro plan".
  def title
    return "#{covered_month.strftime('%B %Y')} usage" if kind == "usage" && covered_month

    label
  end

  # The day Stripe billed it.
  def billed_on
    (finalized_at || period_end)&.to_date
  end

  # "September 2026 usage · billed Sep 30"
  def full_title
    [ title, billed_on && "billed #{billed_on.strftime('%b %-d')}" ].compact.join(" · ")
  end

  # Stripe has started taking the money (a bank debit takes a few business
  # days to land): its line is already on CocoScout's Stripe statement.
  def collection_line
    return @collection_line if defined?(@collection_line)

    @collection_line = StripeBalanceTransaction.where(matched: self, category: "billing").order(:occurred_at).last
  end

  def collecting?
    status == "open" && failed_at.nil? && collection_line.present?
  end

  def lands_on
    collection_line&.available_on
  end

  def failed?
    status == "uncollectible" || (status == "open" && failed_at.present?)
  end
end

# frozen_string_literal: true

# What Stripe billed an organization: its Pro plan, or its monthly usage
# ($3 per performer paid, $5 per staff member scheduled). Mirrored from
# Stripe by BillingInvoiceSync (invoice webhooks plus a nightly sweep), so
# CocoScout knows every bill it sent, and whether it was paid, without
# opening Stripe.
class BillingInvoice < ApplicationRecord
  KINDS = %w[pro usage other].freeze
  STATUSES = %w[draft open paid uncollectible void].freeze
  # A bank debit lands about four business days after it starts.
  BANK_DEBIT_BUSINESS_DAYS = 4

  belongs_to :organization

  validates :stripe_invoice_id, presence: true, uniqueness: true
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }

  scope :paid, -> { where(status: "paid") }
  scope :unpaid, -> { where(status: %w[open uncollectible]) }
  scope :with_credit, -> { where("credit_notes_cents > 0 OR balance_credited_cents > 0 OR balance_applied_cents > 0") }
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

  # Where the bill stands, in a few words: paid, money on its way and the
  # day it lands, the day it's charged, or its due date.
  def status_label
    case status
    when "paid" then "Paid"
    when "open"
      if failed_at.present? then "Payment failed"
      elsif collecting?
        bank = payment_method_type == "us_bank_account"
        if lands_on then "#{bank ? 'Bank debit' : 'Payment'} lands #{lands_on.strftime('%b %-d')}"
        else bank ? "Bank debit on its way" : "Payment on its way"
        end
      elsif collection_method == "send_invoice" then due_at ? "Due #{due_at.strftime('%b %-d')}" : "Due"
      elsif next_payment_attempt_at&.future? then "Charges #{next_payment_attempt_at.strftime('%b %-d')}"
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

  # When CocoScout earned it: a usage bill on the last day of the month it
  # covers (October's usage is October's money, however late it's paid), a
  # plan bill when its period starts. Paid or not: collecting it is a
  # separate question.
  def earned_at
    if kind == "usage" && (month = covered_month)
      month.end_of_month.in_time_zone.change(hour: 12)
    else
      period_start || finalized_at || paid_at || created_at
    end
  end

  # Sent, not paid, and still owed: what CocoScout has earned but not yet
  # collected. Drafts aren't sent; void bills are gone.
  def self.earned_unpaid
    where(status: %w[open uncollectible]).where.not(id: duplicate_ids)
  end

  # Usage bills that bill a month another bill already carries (an org with
  # two usage subscriptions gets one bill from each): every live usage bill
  # for an org and month after the first.
  def self.duplicate_ids
    where(kind: "usage").where.not(status: "void").order(:id).to_a
                        .group_by { |bill| [ bill.organization_id, bill.covered_month ] }
                        .flat_map { |(_, month), bills| month ? bills.drop(1).map(&:id) : [] }
  end

  def duplicate?
    self.class.duplicate_ids.include?(id)
  end

  # Refunded to the card or bank it was paid from: Stripe's refund lines.
  def refunded_cents
    -StripeBalanceTransaction.where(category: "billing_refund", matched: self).sum(:amount_cents)
  end

  # Given back as credit rather than money: credit notes that didn't refund
  # (or haven't refunded yet), and credit put on the customer's balance while
  # it was being collected.
  def credited_only_cents
    [ credit_notes_cents + balance_credited_cents - refunded_cents, 0 ].max
  end

  # Credit an organization has been given back on its bills that no bill has
  # used up yet: what comes off its next bills.
  def self.unused_credit_cents(scope = all)
    [ -scope.with_credit.sum(&:earned_adjustment_cents), 0 ].max
  end

  # CocoScout's ledger is cash: a bill counts what was paid, less what was
  # refunded. What it earned also counts credit the bill used up and leaves
  # out credit given back on it.
  def earned_adjustment_cents
    balance_applied_cents - credited_only_cents
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

  # Money on its way: Stripe's balance shows the charge, or the payment says
  # it's processing (a bank debit, before Stripe's balance shows it).
  def collecting?
    status == "open" && failed_at.nil? && (payment_status == "processing" || collection_line.present?)
  end

  def lands_on
    return collection_line.available_on if collection_line&.available_on
    return nil unless payment_started_at

    day = payment_started_at.to_date
    days = payment_method_type == "us_bank_account" || payment_method_type.nil? ? BANK_DEBIT_BUSINESS_DAYS : 2
    days.times { day = day.next_day; day = day.next_day while day.saturday? || day.sunday? }
    day
  end

  # Unpaid and not on its way: failed, or older than `after` with no charge
  # coming (no payment in flight, no attempt scheduled, not before its due date).
  def late?(now: Time.current, after: 7.days)
    return false unless status.in?(%w[open uncollectible])
    return true if failed?
    return false if collecting? || next_payment_attempt_at&.>(now) || due_at&.>(now)

    (finalized_at || created_at) < now - after
  end

  def failed?
    status == "uncollectible" || (status == "open" && failed_at.present?)
  end
end

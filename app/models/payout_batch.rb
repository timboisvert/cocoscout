# frozen_string_literal: true

# A batch of payouts an organization sends at once through Stripe Connect.
class PayoutBatch < ApplicationRecord
  STATUSES = %w[draft funding funded processing completed failed canceled].freeze
  TRIGGERS = %w[manual scheduled].freeze
  # Run kinds. "staff_pay" = staffing hours; "performer" = show payouts; "course"
  # = course settlements (instructor pay + the org's leftover revenue). They run
  # on separate schedules, so an org can have one open run of each kind at a time.
  # A "course" run is special: the money is already in CocoScout's balance, so it
  # skips funding entirely and just transfers held funds out. ("balance" is the
  # legacy generic kind.)
  KINDS = %w[staff_pay performer course balance].freeze

  belongs_to :organization
  belongs_to :created_by, class_name: "User", optional: true
  has_many :items, class_name: "PayoutBatchItem", dependent: :destroy
  has_many :payout_contributions, dependent: :destroy
  # Worked-time entries pulled into this run; freeing them if the batch is deleted.
  has_many :staff_time_entries, dependent: :nullify

  validates :status, inclusion: { in: STATUSES }
  validates :trigger, inclusion: { in: TRIGGERS }

  scope :recent, -> { order(created_at: :desc) }
  # "Open" = still accepting contributions (not yet funded/closed).
  scope :open_runs, -> { where(status: "draft") }
  scope :of_kind, ->(kind) { where(kind: kind) }

  # The org's single open run of a given kind — created on first use. This is
  # what "add to payout run" appends to.
  def self.open_for(organization, kind:, created_by: nil)
    organization.payout_batches.of_kind(kind).open_runs.order(:created_at).first ||
      organization.payout_batches.create!(kind: kind, status: "draft", trigger: "manual", created_by: created_by)
  end

  def open?
    status == "draft"
  end

  # Submitted and money moving: funding debit in progress, funded, or paying
  # out. The payee-facing "we've sent it — waiting on the bank" state.
  def in_flight?
    %w[funding funded processing].include?(status)
  end

  # Deposits typically land 2–4 business days after the run is funded (ACH
  # settle + transfer). Mirrors MIN/MAX_BUSINESS_DAYS in pay_confirm_controller.js.
  DEPOSIT_MIN_BUSINESS_DAYS = 2
  DEPOSIT_MAX_BUSINESS_DAYS = 4

  # [earliest, latest] dates a payee can expect the deposit, counted from the
  # payday (freshened to the submit date when the run is funded — see
  # PayoutBatchService.fund!).
  def expected_deposit_range
    base = payday || created_at&.to_date || Date.current
    [ self.class.add_business_days(base, DEPOSIT_MIN_BUSINESS_DAYS),
      self.class.add_business_days(base, DEPOSIT_MAX_BUSINESS_DAYS) ]
  end

  def self.add_business_days(date, count)
    out = date
    added = 0
    while added < count
      out += 1
      added += 1 unless out.saturday? || out.sunday?
    end
    out
  end

  def kind_label
    case kind
    when "performer" then "Performer payouts"
    when "staff_pay" then "Staffing"
    when "course" then "Course payouts"
    else "Payouts"
    end
  end

  # A course run pays out money CocoScout already holds, so there's no funding
  # (ACH/card) step — it goes straight to transferring held funds out.
  def skips_funding?
    kind == "course"
  end

  def recalculate_total!
    update!(total_cents: items.sum(:amount_cents))
  end

  def paid_total_cents
    items.where(status: "paid").sum(:amount_cents)
  end

  def completed?
    status == "completed"
  end

  def display_status
    status.titleize
  end

  # The ordered lifecycle steps for the run-page timeline, each tagged with its
  # state (:done / :current / :failed / :upcoming) based on the current status.
  # A run flows draft -> funding -> funded -> processing -> completed; a failure
  # marks the step it died on (funding vs paying) red.
  TIMELINE = [
    { key: "draft",      label: "Created" },
    { key: "funding",    label: "Funding" },
    { key: "funded",     label: "Funded" },
    { key: "processing", label: "Paying" },
    { key: "completed",  label: "Paid" }
  ].freeze

  def timeline_steps
    keys = TIMELINE.map { |s| s[:key] }
    times = { "draft" => created_at, "completed" => completed_at }

    resolve = lambda do |index|
      case status
      when "completed"
        :done
      when "failed", "canceled"
        failed_index = keys.index(funding_status == "failed" ? "funding" : "processing")
        if index < failed_index then :done
        elsif index == failed_index then (status == "failed" ? :failed : :upcoming)
        else :upcoming
        end
      else
        current = keys.index(status) || 0
        if index < current then :done
        elsif index == current then :current
        else :upcoming
        end
      end
    end

    TIMELINE.each_with_index.map do |step, index|
      { label: step[:label], state: resolve.call(index), at: times[step[:key]] }
    end
  end
end

# frozen_string_literal: true

# A batch of payouts an organization sends at once through Stripe Connect.
class PayoutBatch < ApplicationRecord
  # "partially_paid": funded and some (possibly zero) transfers sent, but at
  # least one person is still owed — usually waiting on their bank. The run
  # stays actionable ("Pay remaining") until every item is paid; only then does
  # it become "completed".
  STATUSES = %w[draft funding funded processing partially_paid completed failed canceled].freeze
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

  # Submitted and money moving: funding debit in progress, funded, paying out,
  # or funded-but-partially-paid. The payee-facing "we've sent it" state.
  def in_flight?
    %w[funding funded processing partially_paid].include?(status)
  end

  # Deposits typically land 2–4 business days after the run is funded (ACH
  # settle + transfer). Mirrors MIN/MAX_BUSINESS_DAYS in pay_confirm_controller.js.
  DEPOSIT_MIN_BUSINESS_DAYS = 2
  DEPOSIT_MAX_BUSINESS_DAYS = 4

  # A payee's very first payment is held longer while our payout provider
  # finishes setting up their account. That hold is counted in calendar days,
  # not business days — running it through add_business_days would overstate it
  # to roughly three weeks.
  FIRST_DEPOSIT_MIN_DAYS = 7
  FIRST_DEPOSIT_MAX_DAYS = 14

  # [earliest, latest] dates a payee can expect the deposit, counted from the
  # payday (freshened to the submit date when the run is funded — see
  # PayoutBatchService.fund!).
  #
  # `from:` overrides that base for callers that know when the money actually
  # moved. An ACH-funded run is submitted days before it settles, so counting a
  # payee's window from payday would quote a date that's already gone by the
  # time the transfer happens.
  def expected_deposit_range(first_payout: false, from: nil)
    base = from || payday || created_at&.to_date || Date.current
    if first_payout
      [ base + FIRST_DEPOSIT_MIN_DAYS.days, base + FIRST_DEPOSIT_MAX_DAYS.days ]
    else
      [ self.class.add_business_days(base, DEPOSIT_MIN_BUSINESS_DAYS),
        self.class.add_business_days(base, DEPOSIT_MAX_BUSINESS_DAYS) ]
    end
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

  # --- Automatic retry of parked payees ---------------------------------------
  # RetryParkedPayoutsJob runs daily at this time; the account.updated webhook
  # also fires it the moment a payee finishes connecting a bank. Kept here so
  # the schedule and the "we'll try again at..." copy can't drift apart.
  AUTO_RETRY_HOUR = 6
  AUTO_RETRY_MINUTE = 15

  # Funded, still owes somebody, and the money is really in — so the only thing
  # standing between a parked payee and their deposit is their bank details.
  def awaiting_bank_connections?
    status == "partially_paid" &&
      (funding_status == "succeeded" || skips_funding?) &&
      items.any? { |i| i.status == "pending" }
  end

  # Somebody parked on this run can be paid right now.
  def ready_to_retry?
    awaiting_bank_connections? &&
      items.any? { |i| i.status == "pending" && i.payee.respond_to?(:can_receive_payouts?) && i.payee.can_receive_payouts? }
  end

  # When the automatic sweep will next look at this run. nil when there's
  # nothing waiting, so callers can render the line only when it means something.
  def next_auto_retry_at
    return nil unless awaiting_bank_connections?

    today = Time.zone.now.change(hour: AUTO_RETRY_HOUR, min: AUTO_RETRY_MINUTE, sec: 0)
    today > Time.zone.now ? today : today + 1.day
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
    status == "partially_paid" ? "Partially paid" : status.titleize
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
      when "partially_paid"
        # Funded; the paying step is mid-way (some paid, some waiting on banks).
        if index <= keys.index("funded") then :done
        elsif index == keys.index("processing") then :current
        else :upcoming
        end
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

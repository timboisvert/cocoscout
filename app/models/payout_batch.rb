# frozen_string_literal: true

# A batch of payouts an organization sends at once through Stripe Connect.
class PayoutBatch < ApplicationRecord
  # "partially_paid": funded and some (possibly zero) transfers sent, but at
  # least one person is still owed — usually waiting on their bank. The run
  # stays actionable ("Pay remaining") until every item is paid; only then does
  # it become "completed".
  STATUSES = %w[draft funding funded processing partially_paid completed failed canceled].freeze
  TRIGGERS = %w[manual scheduled].freeze

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

  # LEGACY: a course-kind run pays out money CocoScout already holds, so it has
  # no funding (ACH/card) step at all. New runs are never created with this
  # kind — course money now rides the performer run as held-funds lines (see
  # #held_cents) — but old course runs still render and pay this way.
  def skips_funding?
    kind == "course"
  end

  # Money on this run's unpaid items that CocoScout already holds for the org —
  # course sales and collected contract payments (see
  # PayoutContribution#held_funds?). Funding the run debits the org's bank only
  # for the remainder (see PayoutBatchService.fund!). Capped per item at the
  # item's amount: performer netting (advances) can settle an item below the sum
  # of its lines, and the bank-debit reduction must never exceed what the run
  # actually pays.
  def held_cents(loaded_items = items.includes(:payout_contributions))
    loaded_items.sum do |item|
      next 0 unless item.status == "pending"

      held = item.payout_contributions.sum do |c|
        !c.excluded_from_payout && c.held_funds? ? c.amount_cents : 0
      end
      held.clamp(0, item.amount_cents)
    end
  end

  # --- Automatic retry of parked payees ---------------------------------------
  # RetryParkedPayoutsJob runs daily at this time; the account.updated webhook
  # also fires it the moment a payee finishes connecting a bank. Kept here so
  # the schedule and the "we'll try again at..." copy can't drift apart.
  AUTO_RETRY_HOUR = 6
  AUTO_RETRY_MINUTE = 15

  # Funded, still owes somebody, and the money is really in — the run is
  # waiting either on a payee's bank details (pending) or on a transfer retry
  # (failed). Both kinds must count: a run whose transfers all failed used to
  # promise "we'll retry at 6:15am" while the sweep only looked at pending
  # items and skipped it forever.
  def awaiting_retry?
    status == "partially_paid" &&
      (funding_status == "succeeded" || skips_funding?) &&
      items.any? { |i| RETRYABLE_ITEM_STATUSES.include?(i.status) }
  end

  RETRYABLE_ITEM_STATUSES = %w[pending failed].freeze

  # Somebody parked on this run can be paid right now.
  def ready_to_retry?
    awaiting_retry? &&
      items.any? { |i| RETRYABLE_ITEM_STATUSES.include?(i.status) && i.payee.respond_to?(:can_receive_payouts?) && i.payee.can_receive_payouts? }
  end

  # When the automatic sweep will next look at this run. nil when there's
  # nothing waiting, so callers can render the line only when it means something.
  def next_auto_retry_at
    return nil unless awaiting_retry?

    today = Time.zone.now.change(hour: AUTO_RETRY_HOUR, min: AUTO_RETRY_MINUTE, sec: 0)
    today > Time.zone.now ? today : today + 1.day
  end

  # --- Money by payee state ---------------------------------------------------
  # Where each dollar on the run sits right now, judged per payee. This is the
  # answer to "why isn't this run done?" — a run's status says "partially paid",
  # the item states say "$250 of it is Ned, who hasn't connected a bank".
  #
  #   :paid     — transferred.
  #   :ready    — payable the moment the run is funded / "Pay remaining" runs:
  #               the payee has a connected bank. A failed transfer with a
  #               connected bank counts here too (the next pass retries it);
  #               it just carries its error.
  #   :waiting  — can't be paid yet: the payee has no connected bank.
  #   :returned — paid, then the payee's bank sent it back.
  ITEM_STATES = %i[ready waiting paid returned].freeze

  ITEM_STATE_LABELS = {
    ready: "Ready to pay",
    waiting: "Waiting on bank info",
    paid: "Paid",
    returned: "Returned by bank"
  }.freeze

  def self.item_state(item)
    case item.status
    when "paid" then :paid
    when "returned" then :returned
    else
      payee = item.payee
      payee.respond_to?(:can_receive_payouts?) && payee.can_receive_payouts? ? :ready : :waiting
    end
  end

  # { state => { cents:, count: } } for every state (zeros included), so
  # callers can lay out fixed boxes/columns without nil checks. Preload
  # `items: :payee` when calling this across many runs, or hand in an
  # already-loaded array of this run's items.
  def money_by_item_state(loaded_items = items)
    out = ITEM_STATES.index_with { { cents: 0, count: 0 } }
    loaded_items.each do |item|
      bucket = out[self.class.item_state(item)]
      bucket[:cents] += item.amount_cents
      bucket[:count] += 1
    end
    out
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

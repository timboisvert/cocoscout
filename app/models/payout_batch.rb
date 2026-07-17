# frozen_string_literal: true

# A batch of payouts an organization sends at once through Stripe Connect.
class PayoutBatch < ApplicationRecord
  STATUSES = %w[draft funding funded processing completed failed canceled].freeze
  TRIGGERS = %w[manual scheduled].freeze
  # Run kinds. "staff_pay" = staffing hours; "performer" = show payouts. They run
  # on separate schedules, so an org can have one open run of each kind at a time.
  # ("balance" is the legacy generic kind.)
  KINDS = %w[staff_pay performer balance].freeze

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

  def kind_label
    case kind
    when "performer" then "Performer payouts"
    when "staff_pay" then "Staffing"
    else "Payouts"
    end
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
end

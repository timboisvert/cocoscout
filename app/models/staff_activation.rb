# frozen_string_literal: true

# A durable record that a staff member was *paid staff pay* through a payout
# run in a given billing month — which is what makes them billable ($5/month).
# The staff analog of PerformerActivation, recorded the moment we pay them
# (PayoutBatchService.record_staff_activation!). Scheduling, notifying or an
# unpaid role never bills. Idempotent per (organization, person, month);
# first_notified_at holds when they were first paid that month (the column
# predates the rule).
class StaffActivation < ApplicationRecord
  belongs_to :organization
  belongs_to :person

  validates :billing_month, presence: true
  validates :person_id, uniqueness: { scope: %i[organization_id billing_month] }

  scope :for_month, ->(date) { where(billing_month: date.to_date.beginning_of_month) }

  # Meter a new billable staff member to Stripe (once — only on insert). Async so
  # a Stripe hiccup never blocks a payout run; the nightly reconciliation
  # re-sends anything that didn't land.
  after_create_commit :report_to_meter

  def report_to_meter
    MeterStaffActivationJob.perform_later(id)
  end

  # Record (idempotently) that a person was paid staff pay in `month`.
  def self.record!(organization:, person:, month:, at: Time.current)
    record = find_or_initialize_by(
      organization: organization, person: person, billing_month: month.to_date.beginning_of_month
    )
    record.first_notified_at ||= at
    record.save!
    record
  end
end

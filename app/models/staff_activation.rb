# frozen_string_literal: true

# A durable record that a staff member worked a shift in a paid role in a given
# month — which is what makes them billable ($5/month). Recorded by the hourly
# UsageSweepJob once the shift is over (see UsageRules). Scheduling, an unpaid
# role or a shift still ahead never bills. Idempotent per (organization,
# person, month); first_notified_at holds when that month's first paid shift
# ended (the column predates the rule).
class StaffActivation < ApplicationRecord
  belongs_to :organization
  belongs_to :person

  validates :billing_month, presence: true
  validates :person_id, uniqueness: { scope: %i[organization_id billing_month] }

  scope :for_month, ->(date) { where(billing_month: date.to_date.beginning_of_month) }

  # Meter a new billable staff member to Stripe (once — only on insert). Async so
  # a Stripe hiccup never blocks the sweep; the nightly reconciliation
  # re-sends anything that didn't land.
  after_create_commit :report_to_meter

  def report_to_meter
    MeterStaffActivationJob.perform_later(id)
  end

  # Record (idempotently) that a person worked a paid shift in `month`.
  def self.record!(organization:, person:, month:, at: Time.current)
    record = find_or_initialize_by(
      organization: organization, person: person, billing_month: month.to_date.beginning_of_month
    )
    record.first_notified_at ||= at
    record.save!
    record
  end
end

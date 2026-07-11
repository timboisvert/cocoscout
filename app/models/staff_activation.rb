# frozen_string_literal: true

# A durable, tamper-proof record that a staff member was *notified* of a shift
# in a given billing month — which is what makes them billable ($5/month).
#
# We record this at notification time (schedule finalize) and never delete it,
# so an org can't dodge the charge by removing the assignment before the billing
# cycle closes. Idempotent per (organization, person, month).
class StaffActivation < ApplicationRecord
  belongs_to :organization
  belongs_to :person

  validates :billing_month, presence: true
  validates :person_id, uniqueness: { scope: %i[organization_id billing_month] }

  scope :for_month, ->(date) { where(billing_month: date.to_date.beginning_of_month) }

  # Meter a new billable staff member to Stripe (once — only on insert). Async so
  # a Stripe hiccup never blocks schedule finalize; the nightly reconciliation
  # re-sends anything that didn't land.
  after_create_commit :report_to_meter

  def report_to_meter
    MeterStaffActivationJob.perform_later(id)
  end

  # Record (idempotently) that a person was notified of a shift in `month`.
  def self.record!(organization:, person:, month:, at: Time.current)
    record = find_or_initialize_by(
      organization: organization, person: person, billing_month: month.to_date.beginning_of_month
    )
    record.first_notified_at ||= at
    record.save!
    record
  end
end

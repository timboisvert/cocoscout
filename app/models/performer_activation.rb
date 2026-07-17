# frozen_string_literal: true

# A durable record that a performer was *paid* through a payout run in a given
# billing month — which is what makes them a billable active performer
# ($3/month). The performer analog of StaffActivation.
#
# We record this the moment we pay them (when a performer run's item is paid),
# so the charge lands in the exact month Stripe bills us the ~$2 active-account
# fee for that payout. Idempotent per (organization, person, month) — paying
# someone twice in a month is still one charge.
class PerformerActivation < ApplicationRecord
  belongs_to :organization
  belongs_to :person

  validates :billing_month, presence: true
  validates :person_id, uniqueness: { scope: %i[organization_id billing_month] }

  scope :for_month, ->(date) { where(billing_month: date.to_date.beginning_of_month) }

  # Meter a new billable performer to Stripe (once — only on insert). Async so a
  # Stripe hiccup never blocks casting; the nightly reconciliation re-sends
  # anything that didn't land.
  after_create_commit :report_to_meter

  def report_to_meter
    MeterPerformerActivationJob.perform_later(id)
  end

  # Record (idempotently) that a performer was paid in `month`.
  def self.record!(organization:, person:, month:, at: Time.current)
    record = find_or_initialize_by(
      organization: organization, person: person, billing_month: month.to_date.beginning_of_month
    )
    record.first_activated_at ||= at
    record.save!
    record
  end
end

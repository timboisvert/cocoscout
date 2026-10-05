# frozen_string_literal: true

# One day's check that CocoScout's records add up to its Stripe balance.
# See PlatformReconciliationCheck for what's compared.
class PlatformReconciliation < ApplicationRecord
  scope :newest_first, -> { order(checked_on: :desc) }

  def self.latest
    newest_first.first
  end

  def clean?
    difference_cents.to_i.zero? && unmatched_count.zero? && mismatch_count.zero? && failed_webhook_count.zero? &&
      details.fetch("import_complete", true)
  end
end

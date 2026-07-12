# frozen_string_literal: true

# Daily: run automatic payouts for every org whose payout schedule falls due
# today. ScheduledPayoutService is idempotent per day, so re-running is safe.
class RunScheduledPayoutsJob < ApplicationJob
  queue_as :background

  def perform(on: Date.current)
    Organization.where.not(payout_schedule: [ nil, "manual" ]).find_each do |organization|
      ScheduledPayoutService.run_due!(organization, on: on)
    end
  end
end

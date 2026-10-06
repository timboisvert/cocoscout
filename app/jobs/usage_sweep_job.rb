# frozen_string_literal: true

# Hourly: everyone whose paid work has just happened becomes billable for its
# month (UsageRules), this month and last (a show payout calculated a few
# days late still lands in the month of the show).
class UsageSweepJob < ApplicationJob
  queue_as :background

  def perform
    [ Date.current.prev_month, Date.current ].each do |month|
      UsageRebuild.run!(month, post: true, remove: false)
    end
  end
end

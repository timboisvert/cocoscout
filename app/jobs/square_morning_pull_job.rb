# frozen_string_literal: true

# Every morning: last night's business day for every connected Square
# account, so the day is filled in before anyone opens Settle up.
#
# The job runs at 5 am, and a business day runs until 6 am by default, so at
# 5 am last night is still the current business day. Asking for "the day
# before the current one" fetched the night before last (found 2026-11-16:
# Monday's 5 am pull read Saturday; only the overnight webhook had brought
# Sunday in, and a day with no shows has nothing else to list it). So it reads the current
# business day and the one before, the way the webhook does: last night
# whichever side of the rollover it runs on, and the night before read again
# whole.
class SquareMorningPullJob < ApplicationJob
  queue_as :background

  def perform
    Integration.connected.square.find_each do |integration|
      current = SettlementDay.day_for(integration.organization, Time.current)
      SquarePullJob.perform_later(integration.id, from: current - 1, to: current, trigger: "morning")
    end
  end
end

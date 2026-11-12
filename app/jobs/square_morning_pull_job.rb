# frozen_string_literal: true

# Every morning: yesterday's business day for every connected Square
# account, so the day is filled in before anyone opens Settle up.
class SquareMorningPullJob < ApplicationJob
  queue_as :background

  def perform
    Integration.connected.square.find_each do |integration|
      yesterday = SettlementDay.day_for(integration.organization, Time.current) - 1
      SquarePullJob.perform_later(integration.id, from: yesterday, to: yesterday, trigger: "morning")
    end
  end
end

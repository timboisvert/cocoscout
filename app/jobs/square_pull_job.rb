# frozen_string_literal: true

# One pull from Square for an integration over a span of business days.
class SquarePullJob < ApplicationJob
  queue_as :background

  def perform(integration_id, from:, to:, trigger: "manual")
    integration = Integration.connected.square.find_by(id: integration_id)
    return unless integration

    SquareSync.pull!(integration, from: from.to_date, to: to.to_date, trigger: trigger)
  end
end

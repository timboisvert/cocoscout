# frozen_string_literal: true

# Reports a single newly-billable performer (a PerformerActivation) to Stripe's
# meter. Enqueued from PerformerActivation#after_create_commit.
class MeterPerformerActivationJob < ApplicationJob
  queue_as :default

  def perform(activation_id)
    activation = PerformerActivation.find_by(id: activation_id)
    return unless activation

    PerformerMeterService.report_activation!(activation)
  end
end

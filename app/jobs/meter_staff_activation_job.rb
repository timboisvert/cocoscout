# frozen_string_literal: true

# Reports a single newly-billable staff member (a StaffActivation) to Stripe's
# meter. Enqueued from StaffActivation#after_create_commit.
class MeterStaffActivationJob < ApplicationJob
  queue_as :default

  def perform(activation_id)
    activation = StaffActivation.find_by(id: activation_id)
    return unless activation

    StaffMeterService.report_activation!(activation)
  end
end

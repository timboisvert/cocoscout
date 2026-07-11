# frozen_string_literal: true

# Reports a pay run's $1 extra-payment fees to Stripe's meter. Enqueued after a
# staff pay run that incurred fees.
class MeterStaffFeeJob < ApplicationJob
  queue_as :default

  def perform(batch_id)
    batch = PayoutBatch.find_by(id: batch_id)
    return unless batch

    StaffMeterService.report_extra_payments!(batch)
  end
end

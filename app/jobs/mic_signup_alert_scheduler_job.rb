# frozen_string_literal: true

# Runs every minute via Solid Queue recurring. Finds alerts whose
# `next_target_at` has elapsed, fires `MicSignupAlertDeliveryJob`, and
# rolls each alert's `next_target_at` forward to the following week.
class MicSignupAlertSchedulerJob < ApplicationJob
  queue_as :background

  def perform
    MicSignupAlert.due.find_each do |alert|
      MicSignupAlertDeliveryJob.perform_later(alert.id)
      alert.update!(last_delivered_at: Time.current, next_target_at: nil)
      alert.recompute_target!
    end
  end
end

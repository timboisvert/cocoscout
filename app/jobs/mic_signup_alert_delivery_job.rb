# frozen_string_literal: true

# Delivers a single mic sign-up alert. V1: email only. The architecture
# pivots to support web_push + native push by adding deliver_web_push and
# deliver_native methods and dispatching on `alert.channels`.
class MicSignupAlertDeliveryJob < ApplicationJob
  queue_as :default

  def perform(alert_id)
    alert = MicSignupAlert.find_by(id: alert_id)
    return unless alert && alert.active && alert.user

    channels = Array(alert.channels)
    deliver_email(alert) if channels.include?("email")
    # Future: deliver_web_push(alert), deliver_native(alert)
  end

  private

  def deliver_email(alert)
    MicSignupAlertMailer.opens_soon(alert).deliver_later
  end
end

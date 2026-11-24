# frozen_string_literal: true

# Daily: remind each organization whose yearly Pro plan renews within 30
# days, once for each renewal (ProRenewalReminder).
class ProRenewalReminderJob < ApplicationJob
  queue_as :background

  def perform(now: Time.current)
    ProRenewalReminder.due(now: now).find_each do |organization|
      ProRenewalReminder.new(organization).send!
    end
  end
end

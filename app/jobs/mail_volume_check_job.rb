# frozen_string_literal: true

# The daily look at how much mail CocoScout has sent against its Mailgun
# plan (MailVolume.check!): superadmins are notified when the month gets
# close to the plan, and when its pace says it's time to move up a plan.
class MailVolumeCheckJob < ApplicationJob
  queue_as :background

  def perform(now: Time.current)
    MailVolume.check!(now: now)
  end
end

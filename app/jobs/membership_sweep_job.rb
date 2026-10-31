# frozen_string_literal: true

# Daily: expired memberships marked, renewal reminders sent
# (Ticketing::Memberships.sweep!).
class MembershipSweepJob < ApplicationJob
  queue_as :default

  def perform
    Ticketing::Memberships.sweep!
    Ticketing::Subscriptions.sweep!
  end
end

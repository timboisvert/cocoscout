# frozen_string_literal: true

# A superadmin asked for a fresh check: import from Stripe, then check. No
# email; they're looking at the page.
class PlatformCheckNowJob < ApplicationJob
  queue_as :default

  def perform
    StripeBalanceImport.run!
    PlatformReconciliationCheck.run!
  end
end

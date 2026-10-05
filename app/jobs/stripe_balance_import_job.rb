# frozen_string_literal: true

# Hourly: bring in Stripe's newest balance lines and match them.
class StripeBalanceImportJob < ApplicationJob
  queue_as :background

  def perform
    StripeBalanceImport.run!
  rescue Stripe::AuthenticationError
    # No Stripe key here (a fresh checkout): nothing to import.
    nil
  end
end

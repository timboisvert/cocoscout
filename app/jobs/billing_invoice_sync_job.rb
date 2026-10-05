# frozen_string_literal: true

# Nightly: every bill Stripe sent every org, in case a webhook went missing.
class BillingInvoiceSyncJob < ApplicationJob
  queue_as :background

  def perform
    BillingInvoiceSync.sync_all!
  end
end

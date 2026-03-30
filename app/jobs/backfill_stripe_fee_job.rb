# frozen_string_literal: true

# Backfills missing Stripe fee data for course registrations.
#
# When a payment completes, we try to fetch the Stripe fee immediately via the webhook handler.
# However, Stripe's balance transaction isn't always available instantly, so the initial fetch
# might fail. This job retries the fetch for all registrations with missing stripe_fee_cents,
# allowing time for the data to become available.
#
# Runs hourly. Safe to run multiple times — uses idempotent updates (only updates if nil).
#
class BackfillStripeFeeJob < ApplicationJob
  queue_as :default

  # Batch size for processing (balance transaction fetches are quick)
  BATCH_SIZE = 25
  # Delay between batches to respect Stripe rate limits (100/sec max, we're being conservative)
  BATCH_DELAY = 0.1

  def perform
    registrations = CourseRegistration.where(stripe_fee_cents: nil)
      .where.not(stripe_payment_intent_id: nil)
      .order(:id)

    count = registrations.count
    return unless count.positive?

    Rails.logger.info "[BackfillStripeFeeJob] Found #{count} registrations missing Stripe fee data"

    successful = 0
    failed = 0

    registrations.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      batch.each do |registration|
        if fetch_and_update_stripe_fee(registration)
          successful += 1
        else
          failed += 1
        end
      end

      # Sleep between batches to avoid hitting rate limits
      sleep(BATCH_DELAY)
    end

    Rails.logger.info "[BackfillStripeFeeJob] Completed: #{successful} updated, #{failed} failed"
  end

  private

  def fetch_and_update_stripe_fee(registration)
    payment_intent_id = registration.stripe_payment_intent_id
    return false unless payment_intent_id.present?

    payment_intent = Stripe::PaymentIntent.retrieve(payment_intent_id)
    charge_id = payment_intent.latest_charge
    return false unless charge_id

    charge = Stripe::Charge.retrieve(charge_id)
    balance_transaction_id = charge.balance_transaction
    return false unless balance_transaction_id

    balance_transaction = Stripe::BalanceTransaction.retrieve(balance_transaction_id)
    registration.update!(stripe_fee_cents: balance_transaction.fee)

    true
  rescue Stripe::StripeError => e
    Rails.logger.warn "[BackfillStripeFeeJob] Failed to fetch fee for registration #{registration.id}: #{e.message}"
    false
  rescue StandardError => e
    Rails.logger.error "[BackfillStripeFeeJob] Unexpected error for registration #{registration.id}: #{e.message}"
    false
  end
end

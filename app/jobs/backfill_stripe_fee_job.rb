# frozen_string_literal: true

# Backfills missing Stripe fee data for course registrations, ticket orders
# and contract payments paid through CocoScout.
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
    perform_for_ticket_orders
    perform_for_contract_payments

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

  # Ticket orders paid through CocoScout whose Stripe fee hasn't landed yet
  # (superadmin Finances reads it for the processing margin).
  def perform_for_ticket_orders
    # An exchange's new order carries no payment of its own: the fee is on the original.
    orders = TicketOrder.where(stripe_fee_cents: nil, money_path: "cocoscout", status: TicketOrder::WAS_PAID, exchanged_from_id: nil)
                        .where.not(stripe_payment_intent_id: nil).where("total_cents > 0").order(:id)
    orders.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      batch.each { |order| fetch_and_update_stripe_fee(order) }
      sleep(BATCH_DELAY)
    end
  end

  # Contract payments collected online whose fee couldn't be read when they
  # settled: they were credited to the org gross. Once the fee is known the
  # org's credit is restated to what it really is (amount less the fee).
  def perform_for_contract_payments
    payments = ContractPayment.status_paid.direction_incoming.where(stripe_fee_cents: nil)
                              .where.not(stripe_payment_intent_id: nil).order(:id)
    payments.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      batch.each do |payment|
        next unless fetch_and_update_stripe_fee(payment)
        # Already on its way to the org at the gross amount: CocoScout ate the
        # fee, and the org's credit has to match what it was sent.
        next if PayoutContribution.exists?(source: payment)

        entry = OrgCashEntry.find_by(source: payment, entry_type: "contract_payment")
        entry&.update!(amount_cents: payment.remittable_cents)
      end
      sleep(BATCH_DELAY)
    end
  end

  private

  # registration: a CourseRegistration or a TicketOrder; both carry
  # stripe_payment_intent_id and stripe_fee_cents.
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

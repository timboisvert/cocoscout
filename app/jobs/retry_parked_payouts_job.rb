# frozen_string_literal: true

# Pays the people who were parked on a funded run because they had no bank
# account, once they've connected one — and retries transfers that failed
# outright (a transient Stripe refusal shouldn't strand a funded run).
#
# Their money was debited from the org up front and has been sitting on the run
# ever since. The only way it moved before was a manager noticing the "Pay
# remaining" button had lit up — which meant money could sit indefinitely
# because nobody happened to revisit the page.
#
# Runs daily as a floor. The account.updated webhook enqueues this for a single
# payee the moment they finish onboarding, so the usual case is seconds, not a
# day; this catches anything that path missed.
class RetryParkedPayoutsJob < ApplicationJob
  queue_as :background

  # payee: retry only the runs waiting on this payee (the webhook path).
  # Omitted: sweep every waiting run in the system (the daily path).
  def perform(payee: nil)
    batches = batches_to_check(payee)
    refresh_stale_payees!(batches)

    batches.each do |batch|
      next unless batch.ready_to_retry?

      paid_before = batch.items.where(status: "paid").pluck(:id).to_set
      PayoutBatchService.pay_remaining!(batch)
      newly_paid = batch.items.reload.where(status: "paid").reject { |i| paid_before.include?(i.id) }
      next if newly_paid.empty?

      notify_org(batch, newly_paid)
    rescue StandardError => e
      # One org's failure must never stop the sweep.
      Rails.logger.error("[RetryParkedPayoutsJob] batch #{batch.id}: #{e.class}: #{e.message}")
    end
  end

  private

  def batches_to_check(payee)
    scope = PayoutBatch.where(status: "partially_paid").includes(:organization, items: :payee)
    return scope.to_a unless payee

    scope.select { |b| b.items.any? { |i| PayoutBatch::RETRYABLE_ITEM_STATUSES.include?(i.status) && i.payee == payee } }
  end

  # Our payouts_enabled column is a cached copy of Stripe's answer, kept current
  # by the account.updated webhook. When one of those events is missed — or the
  # account was still being cleared when a transfer was attempted and we parked
  # the item — the copy says "can't be paid" forever and the money sits. Before
  # deciding, re-read the accounts we currently believe are unpayable. One API
  # call per stranded payee, once a day, and only for money already owed.
  def refresh_stale_payees!(batches)
    payees = batches.flat_map { |b| b.items.select { |i| PayoutBatch::RETRYABLE_ITEM_STATUSES.include?(i.status) }.map(&:payee) }
    payees.compact.uniq.each do |payee|
      next unless payee.respond_to?(:can_receive_payouts?) && payee.connect_account_started? && !payee.can_receive_payouts?

      StripeConnectService.new(payee).sync_account
    rescue StandardError => e
      Rails.logger.warn("[RetryParkedPayoutsJob] account re-sync failed for #{payee.class}##{payee.id}: #{e.message}")
    end
  end

  # Money moved without anyone clicking, so it has to leave a trail.
  def notify_org(batch, newly_paid)
    recipients = batch.organization.payout_notification_users.filter_map(&:person)
    return if recipients.empty?

    names = newly_paid.filter_map { |i| i.payee&.name }
    total = newly_paid.sum(&:amount_cents)

    ContentTemplateService.deliver(
      template_key: "payout_auto_retry_paid",
      variables: {
        organization_name: batch.organization.name,
        people: names.to_sentence,
        people_count: ActionController::Base.helpers.pluralize(newly_paid.size, "person"),
        total: ActionController::Base.helpers.number_to_currency(total / 100.0),
        payout_run_url: Rails.application.routes.url_helpers.manage_payout_batch_path(batch)
      },
      sender: nil,
      recipients: recipients,
      organization: batch.organization,
      message_type: :system,
      system_generated: false
    )
  rescue StandardError => e
    Rails.logger.error("[RetryParkedPayoutsJob] notify batch #{batch.id}: #{e.class}: #{e.message}")
  end
end

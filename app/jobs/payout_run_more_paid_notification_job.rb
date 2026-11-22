# frozen_string_literal: true

# A morning's pass over a payout run paying from the CocoScout balance paid
# more people (PayoutBalanceWavesJob): tell the organization's chosen people
# who, and what happens to whoever is left, from the forecast of money
# already sold (PayoutBalanceForecast). A notification, not an email (Tim,
# 2026-11-22; fewer emails). A run the pass finished gets "everyone's paid"
# instead (PayoutRunCompletedNotificationJob).
class PayoutRunMorePaidNotificationJob < ApplicationJob
  include PayoutRunManagerNotice

  queue_as :default

  def perform(payout_batch_id, item_ids)
    batch = PayoutBatch.find_by(id: payout_batch_id)
    return if batch.nil? || batch.completed?

    paid = batch.items.where(id: item_ids, status: "paid").includes(:payee).to_a
    return if paid.empty?

    notify_managers(batch, template_key: "payout_run_more_paid", variables: {
      paid_count: paid.size == 1 ? "1 more payee" : "#{paid.size} more payees",
      paid_names: paid.map { |item| item.payee&.name || "Payee" }.to_sentence,
      paid_total: money(paid.sum(&:amount_cents)),
      next_words: next_words(batch)
    })
  end

  private

  # What happens to whoever is left, in one or two sentences.
  def next_words(batch)
    rest = batch.items.where(status: PayoutBatch::RETRYABLE_ITEM_STATUSES).to_a
    others = "The other #{rest.size} (#{money(rest.sum(&:amount_cents))})"
    if batch.awaiting_balance?
      zone = ActiveSupport::TimeZone[batch.organization.time_zone] || Time.zone
      bank_day = batch.bank_due_at&.in_time_zone(zone)&.to_date
      rows = PayoutBalanceForecast.rows(batch)
      covered = rows.find { |row| row.bank_cents.zero? }
      bank_row = rows.find { |row| row.date == bank_day } || rows.last
      if covered && (bank_day.nil? || covered.date <= bank_day)
        "Ticket money already sold should pay the other #{rest.size} (#{money(rest.sum(&:amount_cents))}) by #{covered.date.strftime('%A, %B %-d')}."
      else
        "#{others} will be paid as ticket money clears. If nothing more sells, your bank will pay " \
          "#{money(bank_row.bank_cents)} on #{(bank_day || bank_row.date).strftime('%A, %B %-d')}."
      end
    elsif rest.all? { |item| !item.payable_now? }
      "#{others} #{rest.size == 1 ? 'is' : 'are'} waiting to connect a bank, and #{rest.size == 1 ? 'is' : 'are'} paid once they do."
    else
      "Your bank is paying the other #{rest.size} (#{money(rest.sum(&:amount_cents))}). They're paid when the debit clears."
    end
  end
end

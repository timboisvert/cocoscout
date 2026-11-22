# frozen_string_literal: true

# A payout run was submitted: tell the organization's chosen people who's
# being paid, how much, and when deposits should land (Notification + email).
# Enqueued from PayoutBatchService.fund! so the request never waits on mail.
# funded: the money settled in the same request (a card, or held money and
# credit covering the whole run), so the words say "submitted and funded"
# and no separate funded notice follows. from_balance: the run paid from the
# CocoScout balance first (PayoutBatchService.start_from_balance!), so the
# words say who was paid now and when the rest are.
class PayoutRunSubmittedNotificationJob < ApplicationJob
  include PayoutRunManagerNotice

  queue_as :default

  def perform(payout_batch_id, funded: false, from_balance: false)
    batch = PayoutBatch.find_by(id: payout_batch_id)
    return unless batch
    # Only runs that actually started funding — a failed fund! never notifies.
    return unless batch.in_flight? || batch.completed?

    items = batch.items.includes(:payee).order(amount_cents: :desc)
    template_key, extra = from_balance ? [ "payout_run_submitted_from_balance", from_balance_variables(batch, items) ] : [ "payout_run_submitted", { funded: funded, not_funded: !funded } ]
    # One delivery per person: the greeting carries their name.
    batch.organization.payout_notification_users.filter_map(&:person).each do |person|
      notify_managers(batch, template_key: template_key, recipients: [ person ], variables: {
        recipient_name: person.name.to_s.split.first.presence || person.name,
        people_count: "#{items.size} #{items.size == 1 ? 'payee' : 'payees'}",
        payee_lines: payee_lines_html(items)
      }.merge(extra))
    end
  end

  private

  # Who the balance paid at submit, and who waits for what.
  def from_balance_variables(batch, items)
    paid = items.select(&:paid_from_balance)
    waiting = items.select { |item| PayoutBatch::RETRYABLE_ITEM_STATUSES.include?(item.status) }
    on_balance = batch.funding_status == "awaiting_balance"
    {
      paid_count: "#{paid.size} #{paid.size == 1 ? 'payee' : 'payees'}",
      paid_total: money(paid.sum(&:amount_cents)),
      waiting_count: waiting.size,
      waiting_total: money(waiting.sum(&:amount_cents)),
      bank_date: batch.bank_due_at&.in_time_zone(batch.organization.time_zone)&.strftime("%B %-d").to_s,
      waiting_on_balance: on_balance && waiting.any?,
      waiting_on_bank: !on_balance && waiting.any?
    }
  end

  # One row per payee: name + amount. Deliberately no per-line breakdown —
  # the linked run page carries the full detail.
  def payee_lines_html(items)
    rows = items.map do |item|
      name = ERB::Util.html_escape(item.payee&.name || "Payee")
      "<tr><td style=\"padding: 6px 16px 6px 0; color: #111827;\">#{name}</td>" \
        "<td style=\"padding: 6px 0; text-align: right; color: #111827; font-weight: 600;\">#{money(item.amount_cents)}</td></tr>"
    end
    '<table style="width: 100%; border-collapse: collapse; background-color: #f9fafb; border-radius: 12px; padding: 16px; margin: 16px 0;"><tbody>' \
      "#{rows.join}</tbody></table>"
  end
end

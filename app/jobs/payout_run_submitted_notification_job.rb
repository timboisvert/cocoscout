# frozen_string_literal: true

# A payout run was submitted: tell the organization's chosen people who's
# being paid, how much, and when deposits should land (Notification + email).
# Enqueued from PayoutBatchService.fund! so the request never waits on mail.
# funded: the money settled in the same request (a card, or held money and
# credit covering the whole run), so the words say "submitted and funded"
# and no separate funded notice follows.
class PayoutRunSubmittedNotificationJob < ApplicationJob
  include PayoutRunManagerNotice

  queue_as :default

  def perform(payout_batch_id, funded: false)
    batch = PayoutBatch.find_by(id: payout_batch_id)
    return unless batch
    # Only runs that actually started funding — a failed fund! never notifies.
    return unless batch.in_flight? || batch.completed?

    items = batch.items.includes(:payee).order(amount_cents: :desc)
    # One delivery per person: the greeting carries their name.
    batch.organization.payout_notification_users.filter_map(&:person).each do |person|
      notify_managers(batch, template_key: "payout_run_submitted", recipients: [ person ], variables: {
        recipient_name: person.name.to_s.split.first.presence || person.name,
        people_count: "#{items.size} #{items.size == 1 ? 'payee' : 'payees'}",
        payee_lines: payee_lines_html(items),
        funded: funded,
        not_funded: !funded
      })
    end
  end

  private

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

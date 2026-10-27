# frozen_string_literal: true

# A payout run finished a paying pass: everyone's paid (status "completed"),
# or some are still waiting on bank details ("partially_paid"), named. Once
# per completion, from PayoutBatchService.finalize_status!; a later Pay
# remaining that pays the rest sends "everyone's paid" after the "partly".
# `status` is what the run became when it was enqueued, so a run that moved
# on by the time the job runs still gets the notice it earned.
class PayoutRunCompletedNotificationJob < ApplicationJob
  include PayoutRunManagerNotice

  queue_as :default

  def perform(payout_batch_id, status)
    batch = PayoutBatch.find_by(id: payout_batch_id)
    return unless batch

    items = batch.items.includes(:payee).to_a
    paid = items.select { |i| i.status == "paid" }
    waiting = items - paid

    case status
    when "completed"
      notify_managers(batch, template_key: "payout_run_completed", variables: {
        total: money(paid.sum(&:amount_cents)),
        people_count: helpers.pluralize(paid.size, "person")
      })
    when "partially_paid"
      notify_managers(batch, template_key: "payout_run_partly_paid", variables: {
        paid_count: helpers.pluralize(paid.size, "person"),
        paid_total: money(paid.sum(&:amount_cents)),
        waiting_count: waiting.size.to_s,
        waiting_names: waiting.map { |i| ERB::Util.html_escape(i.payee&.name || "Payee") }.to_sentence,
        waiting_total: money(waiting.sum(&:amount_cents))
      })
    end
  end
end

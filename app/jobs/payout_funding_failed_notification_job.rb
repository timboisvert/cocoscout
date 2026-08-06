# frozen_string_literal: true

# The ACH debit that was funding a payout run bounced. Nobody was told before —
# the run just sat there marked failed while everyone assumed money was moving,
# and the payees had already been told their money was on its way.
class PayoutFundingFailedNotificationJob < ApplicationJob
  queue_as :default

  def perform(payout_batch_id)
    batch = PayoutBatch.find_by(id: payout_batch_id)
    return unless batch&.funding_status == "failed"

    recipients = batch.organization.payout_notification_users.filter_map(&:person)
    return if recipients.empty?

    ContentTemplateService.deliver(
      template_key: "payout_funding_failed",
      variables: {
        organization_name: batch.organization.name,
        total: ActionController::Base.helpers.number_to_currency(batch.total_cents / 100.0),
        people_count: ActionController::Base.helpers.pluralize(batch.items.count, "person"),
        payout_run_url: Rails.application.routes.url_helpers.manage_payout_batch_path(batch)
      },
      sender: nil,
      recipients: recipients,
      organization: batch.organization,
      message_type: :system,
      system_generated: false
    )
  end
end

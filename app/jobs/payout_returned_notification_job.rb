# frozen_string_literal: true

# A payment reached the payee's account and their bank sent it back — usually a
# closed account or details that don't match. Both sides need to hear it: the
# payee so they can fix their details, the org so they know the money is theirs
# again and still owed.
class PayoutReturnedNotificationJob < ApplicationJob
  queue_as :default

  def perform(payout_batch_item_id)
    item = PayoutBatchItem.find_by(id: payout_batch_item_id)
    return unless item&.returned?

    batch = item.payout_batch
    organization = batch.organization
    amount = ActionController::Base.helpers.number_to_currency(item.amount_cents / 100.0)

    notify_payee(item, organization, amount)
    notify_org(item, batch, organization, amount)
  end

  private

  def notify_payee(item, organization, amount)
    person = payee_person(item)
    return unless person

    ContentTemplateService.deliver(
      template_key: "payout_returned_to_payee",
      variables: {
        recipient_name: person.name,
        organization_name: organization.name,
        amount: amount,
        setup_url: url_helpers.my_payments_setup_url(url_options)
      },
      sender: nil,
      recipients: [ person ],
      organization: organization,
      message_type: :system,
      system_generated: true
    )
  rescue StandardError => e
    Rails.logger.error("[PayoutReturnedNotificationJob] payee #{item.id}: #{e.class}: #{e.message}")
  end

  def notify_org(item, batch, organization, amount)
    recipients = organization.payout_notification_users.filter_map(&:person)
    return if recipients.empty?

    ContentTemplateService.deliver(
      template_key: "payout_returned_manager",
      variables: {
        payee_name: item.payee&.name.to_s,
        organization_name: organization.name,
        amount: amount,
        reason: item.error.to_s,
        payout_run_url: url_helpers.manage_payout_batch_path(batch)
      },
      sender: nil,
      recipients: recipients,
      organization: organization,
      message_type: :system,
      system_generated: false
    )
  rescue StandardError => e
    Rails.logger.error("[PayoutReturnedNotificationJob] org #{item.id}: #{e.class}: #{e.message}")
  end

  # Contractors are paid through their linked Person; an Organization payee
  # (a course run paying the org itself) has nobody to tell.
  def payee_person(item)
    case item.payee
    when Person then item.payee
    when Contractor then item.payee.person
    end
  end

  def url_helpers
    Rails.application.routes.url_helpers
  end

  def url_options
    Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end
end

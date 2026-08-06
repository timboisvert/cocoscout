# frozen_string_literal: true

# A payout to someone's bank failed, but we couldn't tie it to one payment with
# confidence (one Stripe payout can bundle several of our transfers, and it
# reports an amount rather than our id). Rather than guess at an item and
# corrupt the ledger, we tell the humans: the payee to fix their details, the
# org so the discrepancy isn't invisible.
class PayoutAccountProblemNotificationJob < ApplicationJob
  queue_as :default

  def perform(payee_type, payee_id, amount_cents, reason)
    payee = payee_type.safe_constantize&.find_by(id: payee_id)
    return unless payee

    amount = ActionController::Base.helpers.number_to_currency(amount_cents.to_i / 100.0)
    person = payee.is_a?(Contractor) ? payee.person : payee
    return unless person.is_a?(Person)

    # The payee is told once, org-agnostically — their bank details are theirs,
    # not any one organization's.
    organization = recent_organization_for(payee)
    return unless organization

    ContentTemplateService.deliver(
      template_key: "payout_returned_to_payee",
      variables: {
        recipient_name: person.name,
        organization_name: organization.name,
        amount: amount,
        setup_url: Rails.application.routes.url_helpers.my_payments_setup_url(url_options)
      },
      sender: nil,
      recipients: [ person ],
      organization: organization,
      message_type: :system,
      system_generated: true,
      skip_digest: true
    )

    Rails.logger.warn("[PayoutAccountProblemNotificationJob] #{payee_type} #{payee_id}: #{amount} returned — #{reason}")
  end

  private

  def recent_organization_for(payee)
    PayoutBatchItem.where(payee: payee).order(paid_at: :desc).first&.payout_batch&.organization
  end

  def url_options
    Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end
end

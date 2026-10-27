# frozen_string_literal: true

# One way to tell the organization's chosen people (Money settings →
# Notifications) about a payout run: a Notification in the "pay" group for
# each with an account, plus the email the template's channel calls for,
# through PayoutBatchMailer so it really goes. Never from a person.
module PayoutRunManagerNotice
  extend ActiveSupport::Concern

  private

  # recipients: the people to tell (default: everyone chosen). Returns the
  # delivery result, or nil when nobody is chosen.
  def notify_managers(batch, template_key:, variables:, kind: template_key, recipients: nil)
    recipients ||= batch.organization.payout_notification_users.filter_map(&:person)
    return nil if recipients.empty?

    path = url_helpers.manage_payout_batch_path(batch)
    ContentTemplateService.deliver(
      template_key: template_key,
      variables: run_variables(batch).merge(variables),
      sender: nil,
      recipients: recipients,
      organization: batch.organization,
      mailer_class: PayoutBatchMailer.with(organization_id: batch.organization_id),
      mailer_method: :manager_notice,
      # Their email isn't theirs to switch off here: the organization chose them.
      notification: { category: "pay", kind: kind, path: path }
    )
  end

  # What every notice can say about the run.
  def run_variables(batch)
    earliest, latest = batch.expected_deposit_range(from: batch.funded_at&.to_date || batch.payday)
    {
      organization_name: batch.organization.name,
      run_kind: batch.kind_label,
      total: money(batch.total_cents),
      people_count: helpers.pluralize(batch.items.count, "person"),
      payday: (batch.payday || batch.created_at.to_date).strftime("%B %-d"),
      expected_window: "#{earliest.strftime('%B %-d')} – #{latest.strftime('%B %-d, %Y')}",
      payout_run_url: url_helpers.manage_payout_batch_url(batch, **url_options)
    }
  end

  def money(cents)
    helpers.number_to_currency(cents / 100.0)
  end

  def helpers
    ActionController::Base.helpers
  end

  def url_helpers
    Rails.application.routes.url_helpers
  end

  # A job has no request, so a link in an email needs the host handed to it.
  def url_options
    Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end
end

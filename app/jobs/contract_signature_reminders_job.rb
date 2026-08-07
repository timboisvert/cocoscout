# frozen_string_literal: true

# Chases unsigned contracts, then expires them.
#
# A signature request used to sit open forever, so a contract nobody signed was
# indistinguishable from one nobody had looked at. Now each one carries a
# deadline: it gets nudged on a schedule that escalates toward that date, the
# producer hears about it partway through, and when the date passes the link
# actually dies — because a deadline you don't enforce teaches people to ignore
# the next one.
class ContractSignatureRemindersJob < ApplicationJob
  queue_as :background

  def perform(now: Time.current)
    ContractVersion.where.not(sent_for_signature_at: nil)
                   .where(executed_at: nil, expired_at: nil)
                   .includes(contract: :organization)
                   .find_each do |version|
      next unless version.contract&.signing_out_for_signature?

      if version.signature_due_at.present? && version.signature_due_at < now
        expire!(version)
      else
        nudge(version)
      end
    rescue StandardError => e
      Rails.logger.error("[ContractSignatureRemindersJob] version #{version.id}: #{e.class}: #{e.message}")
    end
  end

  private

  def nudge(version)
    number = version.due_nudge_number
    return unless number

    contract = version.contract
    person = contract.signer_person_record
    return unless person

    ContentTemplateService.deliver(
      template_key: "contract_signature_nudge",
      variables: nudge_variables(contract, version),
      sender: nil,
      recipients: [ person ],
      organization: contract.organization,
      mailer_class: Manage::ContractSignatureMailer,
      mailer_method: :signature_request,
      # The last reminder says so in the subject line — an escalation only in
      # the body arrives looking identical to the first one.
      subject_override: final_nudge_subject(contract, version, number),
      message_type: :system,
      system_generated: true
    )
    version.update!(nudge_count: number, last_nudged_at: Time.current)

    # Halfway through the schedule, tell the producer too — they may want to
    # pick up the phone rather than send a fourth email.
    notify_org(contract, version, :stalled) if number == (version.nudge_schedule.size - 1)
  end

  def expire!(version)
    contract = version.contract
    contract.expire_signature_request!
    notify_org(contract, version, :expired)

    person = contract.signer_person_record
    return unless person

    ContentTemplateService.deliver(
      template_key: "contract_signature_expired",
      variables: {
        recipient_name: person.name,
        organization_name: contract.organization.name,
        production_name: contract.production_name.presence || contract.contractor_name
      },
      sender: nil,
      recipients: [ person ],
      organization: contract.organization,
      # A counterparty usually has no CocoScout account — the signing link is
      # public and tokenised for exactly that reason — so the in-app message
      # no-ops for them and email is the only channel that lands. Without a
      # mailer here, the expiry notice reached nobody.
      mailer_class: Manage::ContractSignatureMailer,
      mailer_method: :signature_request,
      message_type: :system,
      system_generated: true
    )
  end

  # nil for every nudge but the last, so the template's own subject is used.
  def final_nudge_subject(contract, version, number)
    return nil unless number == version.nudge_schedule.size

    days = version.days_until_due.to_i
    when_text = days <= 1 ? "tomorrow" : "in #{days} days"
    "Last reminder: your #{contract.organization.name} contract expires #{when_text}"
  end

  def nudge_variables(contract, version)
    days = version.days_until_due
    {
      recipient_name: contract.signer_person_record&.name.to_s,
      organization_name: contract.organization.name,
      production_name: contract.production_name.presence || contract.contractor_name,
      deadline: version.signature_due_at&.strftime("%A, %B %-d"),
      days_left: days.to_i,
      urgency: days.to_i <= 2 ? "This is the last reminder — it expires in #{ActionController::Base.helpers.pluralize(days.to_i, 'day')}." : "",
      sign_url: Rails.application.routes.url_helpers.sign_contract_url(token: contract.signing_token, **url_options)
    }
  end

  def notify_org(contract, version, kind)
    recipients = contract.organization.contract_notification_recipients
    return if recipients.empty?

    ContentTemplateService.deliver(
      template_key: kind == :expired ? "contract_signature_expired_manager" : "contract_signature_stalled_manager",
      variables: {
        contractor_name: contract.contractor_name,
        production_name: contract.production_name.presence || contract.contractor_name,
        organization_name: contract.organization.name,
        deadline: version.signature_due_at&.strftime("%B %-d"),
        contract_url: Rails.application.routes.url_helpers.manage_contract_path(contract)
      },
      sender: nil,
      recipients: recipients,
      organization: contract.organization,
      message_type: :system,
      system_generated: false
    )
  rescue StandardError => e
    Rails.logger.error("[ContractSignatureRemindersJob] notify #{contract.id}: #{e.class}: #{e.message}")
  end

  def url_options
    Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end
end

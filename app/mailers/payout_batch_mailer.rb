# frozen_string_literal: true

# Emails the org's chosen managers when a payout run is submitted (funded):
# who's being paid and how much (names + amounts, no line-item breakdown),
# the expected deposit window, and a link to the run. Copy lives in the
# "payout_run_submitted" ContentTemplate.
class PayoutBatchMailer < ApplicationMailer
  include ActionView::Helpers::SanitizeHelper
  include ActionView::Helpers::NumberHelper

  def submitted(batch:, user:)
    @batch = batch
    # For ApplicationMailer's tracking headers (user / org scoping in email logs).
    @user = user
    @organization = batch.organization
    return unless user&.email_address

    earliest, latest = batch.expected_deposit_range
    items = batch.items.includes(:payee).order(amount_cents: :desc)

    template = ContentTemplateService.render("payout_run_submitted", {
      recipient_name: user.person&.name&.split&.first || user.email_address.split("@").first,
      organization_name: batch.organization.name,
      run_kind: batch.kind_label,
      total: number_to_currency(batch.total_cents / 100.0),
      people_count: "#{items.size} #{items.size == 1 ? 'person' : 'people'}",
      expected_window: "#{earliest.strftime('%B %-d')} – #{latest.strftime('%B %-d, %Y')}",
      payee_lines: payee_lines_html(items),
      payout_run_url: manage_payout_batch_url(batch)
    })

    mail(to: user.email_address, subject: template[:subject]) do |format|
      format.html { render html: template[:body].html_safe, layout: "mailer" }
      format.text { render plain: strip_tags(template[:body]).gsub(/\s+/, " ").strip }
    end
  end

  private

  # One row per payee: name + amount. Deliberately no per-line breakdown —
  # the linked run page carries the full detail.
  def payee_lines_html(items)
    rows = items.map do |item|
      name = ERB::Util.html_escape(item.payee&.name || "Payee")
      amount = number_to_currency(item.amount_cents / 100.0)
      "<tr><td style=\"padding: 6px 16px 6px 0; color: #111827;\">#{name}</td>" \
        "<td style=\"padding: 6px 0; text-align: right; color: #111827; font-weight: 600;\">#{amount}</td></tr>"
    end
    '<table style="width: 100%; border-collapse: collapse; background-color: #f9fafb; border-radius: 12px; padding: 16px; margin: 16px 0;"><tbody>' \
      "#{rows.join}</tbody></table>"
  end
end

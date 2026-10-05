# frozen_string_literal: true

# What the money-check email says: the headline and the list of findings.
class PlatformMoneyCheckContent
  extend ActionView::Helpers::NumberHelper

  def self.url_options
    Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end

  def self.for(row)
    findings = []
    money = ->(cents) { number_to_currency(cents.to_i / 100.0) }
    if row.difference_cents.to_i.nonzero?
      findings << "Stripe holds #{money.call(row.stripe_balance_cents)}; our records account for #{money.call(row.held_for_orgs_cents + row.cocoscout_cents)}. Difference: #{money.call(row.difference_cents)}."
    end
    findings << "Stripe's balance isn't fully imported yet." unless row.details.fetch("import_complete", true)
    findings << "#{row.unmatched_count} Stripe #{'line'.pluralize(row.unmatched_count)} nothing in CocoScout explains." if row.unmatched_count.positive?
    findings << "#{row.mismatch_count} Stripe #{'line'.pluralize(row.mismatch_count)} whose amount disagrees with our record." if row.mismatch_count.positive?
    missing = row.details["missing_count"].to_i
    findings << "#{missing} #{'payment'.pluralize(missing)} of ours with no Stripe line." if missing.positive?
    findings << "#{row.failed_webhook_count} Stripe #{'webhook'.pluralize(row.failed_webhook_count)} failed and #{row.failed_webhook_count == 1 ? 'is' : 'are'} waiting on a retry." if row.failed_webhook_count.positive?
    {
      "headline" => findings.first.to_s.truncate(80),
      "findings" => "<ul>#{findings.map { |f| "<li>#{ERB::Util.html_escape(f)}</li>" }.join}</ul>",
      "check_url" => Rails.application.routes.url_helpers.finances_stripe_check_url(**url_options)
    }
  end
end

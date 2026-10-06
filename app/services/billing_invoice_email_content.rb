# frozen_string_literal: true

# What the bill and receipt emails say about one CocoScout bill.
class BillingInvoiceEmailContent
  def self.for(invoice, owner)
    money = ->(cents) { ActiveSupport::NumberHelper.number_to_currency(cents.to_i / 100.0) }
    url_options = Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
    lines = Array(invoice.lines).reject { |line| line["amount_cents"].to_i.zero? }
    {
      "first_name" => owner.person&.name.to_s.split.first.presence || "there",
      "organization_name" => invoice.organization.name,
      "bill_title" => invoice.title,
      "amount" => money.call(invoice.status == "paid" ? invoice.amount_paid_cents : invoice.amount_due_cents),
      "paid_on" => invoice.paid_at&.strftime("%B %-d, %Y").to_s,
      "lines" => lines.any? ? "<ul>#{lines.map { |l| "<li>#{ERB::Util.html_escape(l['description'])}: #{money.call(l['amount_cents'])}</li>" }.join}</ul>" : "",
      "how_paid" => "It's paid automatically from the payment method on file with CocoScout (for usage, the bank account you fund payout runs from) in the next few days. Nothing to do.",
      "invoice_url" => invoice.hosted_invoice_url.presence || Rails.application.routes.url_helpers.section_manage_organization_url(invoice.organization, section: "billing", **url_options),
      "billing_url" => Rails.application.routes.url_helpers.section_manage_organization_url(invoice.organization, section: "billing", **url_options)
    }
  end
end

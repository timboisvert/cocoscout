# frozen_string_literal: true

# The Books notices that aren't one job's own "it's ready" (Tim, 2026-11-09):
# an invoice paid on its page, and background work that didn't finish. The
# words are BooksTemplates. A notice that can't be sent is logged and never
# fails the work it is about.
class BooksNotices
  class << self
    # Paid on the invoice's page: whoever made the invoice hears (the
    # Notifications list and a push; no email), or the owner when that person
    # can no longer see invoices. A payment recorded by hand tells nobody:
    # the person recording it is looking at it.
    def invoice_paid(invoice, payment)
      organization = invoice.organization
      user = [ invoice.created_by, organization.owner ].compact.find { |u| OrganizationAccess.allows?(u, organization, :bills_invoices, :view) }
      return unless user

      money = ->(cents) { ActiveSupport::NumberHelper.number_to_currency(cents / 100.0) }
      Notifier.deliver(
        user: user, category: "books", kind: "invoice_paid", template_key: "invoice_paid_online",
        variables: { recipient_name: (user.person&.name.presence || "there"), organization_name: organization.name, payer_name: invoice.bill_to_name,
                     amount: money.call(payment.amount_cents), invoice_number: invoice.display_number,
                     still_owed: (invoice.unpaid_cents.positive? ? money.call(invoice.unpaid_cents) : ""),
                     invoice_url: urls.manage_money_invoice_url(invoice, **url_options) },
        path: urls.manage_money_invoice_path(invoice), organization: organization, subject: invoice
      )
    rescue StandardError => e
      Rails.logger.error("[BooksNotices] invoice #{invoice.id} paid, notice not sent: #{e.class}: #{e.message}")
    end

    # Work in the background that didn't finish, to whoever asked for it.
    def failed(template_key, user:, organization:, path:, subject: nil, **variables)
      return unless user

      Notifier.deliver(
        user: user, category: "books", kind: template_key, template_key: template_key,
        variables: { recipient_name: (user.person&.name.presence || "there"), organization_name: organization.name }.merge(variables),
        path: path, organization: organization, subject: subject
      )
    rescue StandardError => e
      Rails.logger.error("[BooksNotices] #{template_key} not sent: #{e.class}: #{e.message}")
    end

    def urls = Rails.application.routes.url_helpers
    def url_options = Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end
end

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

    # The nightly check found books that disagree with their records
    # (BooksReconciliationJob), new or changed since the superadmins were
    # last told. A disagreement is a posting CocoScout missed or made twice,
    # so it's ours to chase before the organization asks. A notification to
    # each superadmin (Tim, 2026-11-09: "go ahead"; no email, as for every
    # new notice), whose own page lists each organization and account.
    # found: [[organization, [BooksReconciliation::Mismatch, ...]], ...]
    def books_disagree(found)
      found = found.select { |_, mismatches| mismatches.any? }
      return if found.empty?

      money = ->(cents) { ActiveSupport::NumberHelper.number_to_currency(cents / 100.0) }
      name = ->(mismatch) { ChartOfAccounts::SYSTEM.dig(mismatch.account.to_sym, :name) || mismatch.account }
      escape = ->(words) { ERB::Util.html_escape(words) }
      items = found.map do |organization, mismatches|
        lines = mismatches.map { |m| "<li>#{escape.call(name.call(m))}: books say #{money.call(m.books_cents)}, records say #{money.call(m.expected_cents)} (off by #{money.call(m.difference_cents.abs)})</li>" }
        %(<li><a href="#{urls.organization_detail_url(organization, **url_options)}">#{escape.call(organization.name)}</a><ul>#{lines.join}</ul></li>)
      end
      organization, mismatches = found.first
      headline =
        if found.size > 1 then "#{found.size} organizations' books don't agree with their records"
        else "#{organization.name}, #{name.call(mismatches.first)} off by #{money.call(mismatches.first.difference_cents.abs)}#{" and #{mismatches.size - 1} more" if mismatches.size > 1}"
        end
      rendered = ContentTemplateService.render("books_check_mismatch", { "headline" => headline, "findings" => "<ul>#{items.join}</ul>" })
      User.where(email_address: User::SUPERADMIN_EMAILS).find_each do |user|
        Notifier.deliver_rendered(user: user, category: "books", kind: "books_check_mismatch", subject: rendered[:subject], body: rendered[:body])
      end
    rescue StandardError => e
      Rails.logger.error("[BooksNotices] books check alert not sent: #{e.class}: #{e.message}")
    end

    def urls = Rails.application.routes.url_helpers
    def url_options = Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end
end

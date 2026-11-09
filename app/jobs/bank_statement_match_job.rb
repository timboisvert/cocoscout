# frozen_string_literal: true

# Matches a statement's lines to the books after the upload (Books V1.3,
# plan D3; Tim, 2026-11-02: the import was one heavy request). An older
# line still open gets another look too when money recorded since the last
# statement may explain it (BankStatementMatcher.lines_to_match), but not
# every open line every time: an organization with a year waiting would
# pay for the whole year on each file. matched_at is when this matching
# began, so the next statement knows what "since" means. Then the person
# who brought the file in is told what was found, or that the matching
# didn't finish (Tim, 2026-11-09: only the Bank page said so). Telling them
# is outside the rescue: a notice that can't be sent must not turn a
# statement that matched into one that failed.
class BankStatementMatchJob < ApplicationJob
  queue_as :default

  def perform(import_id)
    import = BankStatementImport.find_by(id: import_id)
    return unless import

    match(import)
    notify(import, import.bank_statement_lines)
  end

  private

  def match(import)
    org = import.organization
    began = Time.current
    since = org.bank_statement_imports.where.not(id: import.id).maximum(:matched_at)
    BankStatementMatcher.run!(org, BankStatementMatcher.lines_to_match(org, import, since: since))
    # Then the organization's rules, over what the matching left open.
    BankRules.apply!(org, rules: org.bank_rules.on_import.order(:id).to_a, lines: org.bank_statement_lines.where(state: "open").to_a, by: import.imported_by)
    lines = import.bank_statement_lines
    import.update!(status: "ready", error: nil, matched_at: began, matched_count: lines.where(state: "matched").count, suggested_count: lines.where(state: "suggested").count)
  rescue StandardError => e
    import.update_columns(status: "failed", error: e.message.truncate(255), updated_at: Time.current)
    BooksNotices.failed("bank_statement_failed", user: import.imported_by, organization: import.organization, subject: import,
                        path: Rails.application.routes.url_helpers.manage_money_bank_path,
                        statement: import.title, bank_url: Rails.application.routes.url_helpers.manage_money_bank_url(**url_options))
    raise
  end

  def notify(import, lines)
    user = import.imported_by
    return unless user

    to_deal_with = lines.where(state: %w[open suggested]).count
    Notifier.deliver(
      user: user, category: "books", kind: "bank_statement_ready", template_key: "bank_statement_ready",
      variables: { recipient_name: (user.person&.name.presence || "there"), organization_name: import.organization.name, statement: import.title,
                   lines: import.new_lines_count, matched: import.matched_count, suggested: import.suggested_count,
                   to_deal_with: to_deal_with, bank_url: Rails.application.routes.url_helpers.manage_money_bank_url(**url_options) },
      path: Rails.application.routes.url_helpers.manage_money_bank_path, organization: import.organization, subject: import
    )
  end

  def url_options
    Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end
end

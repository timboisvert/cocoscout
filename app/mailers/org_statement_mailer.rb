# frozen_string_literal: true

# A theater's monthly CocoScout statement, PDF attached. Words from the
# org_monthly_statement template (PlatformTemplates).
class OrgStatementMailer < ApplicationMailer
  def statement(statement, to:, first_name:)
    totals = statement.totals
    money = ->(cents) { ActiveSupport::NumberHelper.number_to_currency(cents.to_i / 100.0) }
    rendered = ContentTemplateService.render("org_monthly_statement", {
      "first_name" => first_name, "organization_name" => statement.organization.name, "month" => statement.label,
      "total_paid" => money.call(totals["total_paid_cents"]), "opening" => money.call(totals["opening_cents"]),
      "closing" => money.call(totals["closing_cents"]),
      "billing_url" => Rails.application.routes.url_helpers.section_manage_organization_url(statement.organization, section: "billing", **url_options)
    })
    attachments[statement.filename] = { mime_type: "application/pdf", content: statement.pdf.download } if statement.pdf.attached?
    mail(to: to, subject: rendered[:subject]) do |format|
      format.html { render html: rendered[:body].to_s.html_safe, layout: "mailer" }
    end
  end

  private

  def url_options
    Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end
end

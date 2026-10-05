# frozen_string_literal: true

# Makes (or remakes) one theater's statement for a month: the totals, the
# PDF, and, the first time only, the email to the owner.
class OrgStatementJob < ApplicationJob
  queue_as :default

  def perform(organization_id, month_iso, email: true)
    organization = Organization.find_by(id: organization_id)
    return unless organization

    month = Date.iso8601(month_iso).beginning_of_month
    statement = OrgStatement.find_or_initialize_by(organization: organization, month: month)
    statement.update!(totals: OrgStatementBuilder.totals(organization, month), generated_at: Time.current)
    statement.pdf.attach(io: StringIO.new(OrgStatementPdf.new(statement).render), filename: statement.filename, content_type: "application/pdf")
    return unless email && statement.emailed_at.nil?

    owner = organization.owner
    return if owner&.email_address.blank?

    first_name = owner.person&.name.to_s.split.first.presence || "there"
    OrgStatementMailer.statement(statement, to: owner.email_address, first_name: first_name).deliver_now
    statement.update!(emailed_at: Time.current)
  end
end

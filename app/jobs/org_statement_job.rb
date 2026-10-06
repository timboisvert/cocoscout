# frozen_string_literal: true

# Makes (or remakes) one theater's statement for a month: the totals, the
# PDF, and, the first time only, the email to the billing contacts.
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

    contacts = organization.billing_contacts
    return if contacts.empty?

    contacts.each do |contact|
      OrgStatementMailer.statement(statement, to: contact.email, first_name: contact.first_name).deliver_now
    end
    statement.update!(emailed_at: Time.current)
  end
end

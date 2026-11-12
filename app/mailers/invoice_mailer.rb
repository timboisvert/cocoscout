# frozen_string_literal: true

# An invoice, reminder or receipt of either kind, from "ORG via CocoScout",
# with the PDF attached. The words arrive rendered (InvoiceDelivery);
# replies go to the organization's invoice email.
class InvoiceMailer < ApplicationMailer
  def invoice_email(invoice, to:, subject:, body_html:)
    @organization = invoice.organization
    @production = invoice.contract_payment&.contract&.production
    attachments[invoice.filename] = { mime_type: "application/pdf", content: InvoicePdf.new(invoice.document(pdf: true)).render }
    mail(to: to, subject: subject,
         from: email_address_with_name("info@cocoscout.com", "#{@organization.name} via CocoScout"),
         reply_to: @organization.invoice_reply_to) do |format|
      format.html { render html: body_html.html_safe, layout: "mailer" }
    end
  end
end

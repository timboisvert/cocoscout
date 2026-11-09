# frozen_string_literal: true

# Sends an invoice to whoever owes it, whichever kind it is (one the
# organization wrote, or a contract payment's): the invoice, then reminders,
# only when a manager presses Send, and the receipt on its own when it's
# paid. From "ORG via CocoScout" with the PDF attached. A payer with a
# CocoScout account also gets the same words as a message. The words are
# InvoiceTemplates; what goes in them is the invoice's terms.
class InvoiceDelivery
  # The invoice or a reminder. note: what a manager typed at send, where the
  # kind takes one. Returns the address it went to, or nil when there's
  # nowhere to send it.
  def self.send_invoice!(invoice, sender: nil, note: nil)
    new(invoice).send_invoice!(sender: sender, note: note)
  end

  # Once per invoice. Returns the address, or nil.
  def self.send_receipt!(invoice)
    new(invoice).send_receipt!
  end

  def initialize(invoice)
    @invoice = invoice
    @terms = invoice.terms
    @organization = invoice.organization
  end

  def send_invoice!(sender: nil, note: nil)
    key = @terms.template(@invoice.sent_count.zero? ? :invoice : :reminder)
    to = deliver(key, base_variables.merge(@terms.invoice_variables(note)), sender: sender)
    @invoice.update!(sent_at: Time.current, sent_count: @invoice.sent_count + 1) if to
    to
  end

  def send_receipt!
    return nil if @invoice.receipt_emailed_at.present? || !@terms.paid?

    to = deliver(@terms.template(:receipt), base_variables.merge(@terms.receipt_variables), sender: @organization.owner)
    @invoice.update!(receipt_emailed_at: Time.current) if to
    to
  end

  private

  def deliver(key, variables, sender:)
    to = @terms.recipient_email.to_s
    return nil if to.blank? || !to.match?(URI::MailTo::EMAIL_REGEXP)

    subject = ContentTemplateService.render_subject(key, variables)
    body = ContentTemplateService.render_body(key, variables.transform_values { |value| ERB::Util.html_escape(value.to_s) })
    InvoiceMailer.invoice_email(@invoice, to: to, subject: subject, body_html: body.to_s).deliver_later

    if (person = @terms.inbox_person) && sender
      MessageService.create_message(sender: sender, recipients: [ person ], subject: subject, body: body.to_s,
                                    template_key: key, push_body: ContentTemplateService.render_push_body(key, variables),
                                    message_type: :system, organization: @organization, production: @terms.production,
                                    system_generated: true,
                                    # A note from the manager makes it a Message from them too (V1.1 plan §9).
                                    custom_words: ManagerWords.note?(variables[:custom_message]))
    end
    to
  end

  def base_variables
    {
      payer_name: @terms.payer_name,
      organization_name: @organization.name,
      invoice_number: @invoice.display_number,
      amount: ActiveSupport::NumberHelper.number_to_currency(@terms.total_cents / 100.0),
      description: @terms.description,
      invoice_url: @terms.page_url,
      invoice_pdf_url: @terms.pdf_url
    }
  end
end

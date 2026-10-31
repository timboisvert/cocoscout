# frozen_string_literal: true

# Sends an invoice to whoever it's for: the invoice (then reminders) when a
# manager presses Send, and the receipt on its own when it's paid. From
# "ORG via CocoScout" with the PDF attached; words from InvoiceTemplates.
class InvoiceDelivery
  PAID_VIA = { "online" => "online", "cash" => "in cash", "check" => "by check", "zelle" => "by Zelle", "venmo" => "by Venmo", "bank_transfer" => "by bank transfer" }.freeze

  def self.send_invoice!(invoice, sender: nil)
    new(invoice).send_invoice!(sender: sender)
  end

  def self.send_receipt!(invoice)
    new(invoice).send_receipt!
  end

  def initialize(invoice)
    @invoice = invoice
    @organization = invoice.organization
  end

  def send_invoice!(sender: nil)
    key = @invoice.sent_count.zero? ? "invoice" : "invoice_reminder"
    to = deliver(key, base_variables.merge(due_date: @invoice.due_on.strftime("%B %-d, %Y"), custom_message: @invoice.memo.to_s.strip, ways_to_pay: @invoice.ways_to_pay))
    @invoice.update!(sent_at: Time.current, sent_count: @invoice.sent_count + 1) if to
    to
  end

  def send_receipt!
    return nil if @invoice.receipt_emailed_at.present? || !@invoice.paid?

    last = @invoice.invoice_payments.order(:on, :id).last
    to = deliver("invoice_receipt", base_variables.merge(paid_on: (@invoice.paid_on || Date.current).strftime("%B %-d, %Y"), paid_via: PAID_VIA[last&.via].to_s))
    @invoice.update!(receipt_emailed_at: Time.current) if to
    to
  end

  private

  def base_variables
    url_options = Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
    token = @invoice.payment_token!
    {
      payer_name: @invoice.bill_to_attention.presence || @invoice.bill_to_name,
      organization_name: @organization.name,
      invoice_number: @invoice.display_number,
      amount: ActiveSupport::NumberHelper.number_to_currency(@invoice.total_cents / 100.0),
      description: @invoice.invoice_lines.first&.description.to_s,
      invoice_url: Rails.application.routes.url_helpers.pay_invoice_url(token: token, **url_options),
      invoice_pdf_url: Rails.application.routes.url_helpers.pay_invoice_pdf_url(token: token, format: :pdf, **url_options)
    }
  end

  def deliver(key, variables)
    to = @invoice.bill_to_email.to_s
    return nil if to.blank? || !to.match?(URI::MailTo::EMAIL_REGEXP)

    subject = ContentTemplateService.render_subject(key, variables)
    body = ContentTemplateService.render_body(key, variables.transform_values { |value| ERB::Util.html_escape(value.to_s) })
    InvoiceMailer.invoice_email(@invoice, to: to, subject: subject, body_html: body.to_s).deliver_later
    to
  end
end

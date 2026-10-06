# frozen_string_literal: true

# Sends a contract invoice to whoever owes it: the invoice (or, after the first
# send, a reminder) only when a manager presses Send, and the receipt on its
# own when the payment is paid. The email comes from "ORG via CocoScout" with
# the invoice PDF attached; payers with a CocoScout account also get the same
# words as an in-app message. Words from ContractInvoiceTemplates.
class ContractInvoiceDelivery
  # How it was paid, in a sentence: "on October 3 (by check)".
  PAID_VIA = {
    "online" => "online", "cash" => "in cash", "check" => "by check", "zelle" => "by Zelle",
    "venmo" => "by Venmo", "bank_transfer" => "by bank transfer"
  }.freeze

  # The invoice or a reminder. Returns the address it went to, or nil when
  # there's nowhere to send it.
  def self.send_invoice!(invoice, sender:, note: nil)
    new(invoice).send_invoice!(sender: sender, note: note)
  end

  # Once per invoice. Returns the address, or nil.
  def self.send_receipt!(invoice)
    new(invoice).send_receipt!
  end

  def initialize(invoice)
    @invoice = invoice
    @payment = invoice.contract_payment
    @contract = @payment.contract
    @organization = invoice.organization
  end

  def send_invoice!(sender:, note: nil)
    key = @invoice.sent_count.zero? ? "contract_invoice" : "contract_invoice_reminder"
    variables = base_variables.merge(
      due_date: @payment.due_date.strftime("%B %-d, %Y"),
      custom_message: note.to_s.strip,
      other_payment_methods: @contract.offline_payment_methods_sentence.to_s
    )
    to = deliver(key, variables, sender: sender)
    @invoice.update!(sent_at: Time.current, sent_count: @invoice.sent_count + 1) if to
    to
  end

  def send_receipt!
    return nil if @invoice.receipt_emailed_at.present? || !@payment.status_paid?

    variables = base_variables.merge(
      paid_on: (@payment.paid_date || Date.current).strftime("%B %-d, %Y"),
      paid_via: PAID_VIA[@payment.payment_method].to_s
    )
    to = deliver("contract_payment_receipt", variables, sender: @organization.owner)
    @invoice.update!(receipt_emailed_at: Time.current) if to
    to
  end

  # The email on the contract, else the contractor's own.
  def recipient_email
    @contract.contractor_email.presence || @contract.contractor&.email.presence
  end

  private

  def deliver(key, variables, sender:)
    to = recipient_email
    return nil if to.blank? || !to.match?(URI::MailTo::EMAIL_REGEXP)

    subject = ContentTemplateService.render_subject(key, variables)
    body = ContentTemplateService.render_body(key, variables.transform_values { |value| ERB::Util.html_escape(value.to_s) })
    ContractInvoiceMailer.invoice_email(@invoice, to: to, subject: subject, body_html: body.to_s).deliver_later

    if (person = @contract.signer_member_person) && sender
      MessageService.create_message(sender: sender, recipients: [ person ], subject: subject, body: body.to_s,
                                    message_type: :system, organization: @organization, production: @contract.production,
                                    system_generated: true)
    end
    to
  end

  def base_variables
    token = @payment.payment_token!
    {
      payer_name: @contract.contractor_name.presence || "there",
      organization_name: @organization.name,
      invoice_number: @invoice.display_number,
      amount: ActiveSupport::NumberHelper.number_to_currency(@payment.amount.to_f),
      description: @payment.display_name,
      invoice_url: routes.pay_contract_url(token: token, **link_options),
      invoice_pdf_url: routes.pay_contract_invoice_url(token: token, format: :pdf, **link_options)
    }
  end

  def routes
    Rails.application.routes.url_helpers
  end

  def link_options
    Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end
end

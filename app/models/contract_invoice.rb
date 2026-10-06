# frozen_string_literal: true

# The invoice for one payment someone owes an organization under a contract.
# The pay page (/pay/contract/:token) is the invoice, and its PDF is the same
# document. The number (SG-0012) is issued the first time anyone opens it:
# the pay page, the PDF, a manager sending it, or the payment being paid.
# Numbers go in order per organization and are never reused; an invoice whose
# payment was combined into another, removed or cancelled stays, as void.
class ContractInvoice < ApplicationRecord
  belongs_to :organization
  belongs_to :contract_payment, optional: true, inverse_of: :contract_invoice
  belongs_to :combined_into_payment, class_name: "ContractPayment", optional: true

  validates :number, presence: true, uniqueness: { scope: :organization_id }
  validates :prefix, presence: true

  # This payment's invoice, issuing it if it has none yet.
  def self.for!(payment)
    payment.contract_invoice || issue!(payment)
  end

  # The organization's counter row is locked while the number is taken, so
  # two invoices issued at once can't get the same one.
  def self.issue!(payment)
    organization = payment.contract.organization
    invoice = transaction do
      organization.lock!
      find_by(contract_payment_id: payment.id) || begin
        number = organization.invoice_next_number
        organization.update_columns(invoice_next_number: number + 1)
        create!(organization: organization, contract_payment: payment, number: number,
                prefix: organization.invoice_prefix_or_default, payment_token: payment.payment_token!,
                issued_at: Time.current)
      end
    end
    payment.association(:contract_invoice).target = invoice
    invoice
  rescue ActiveRecord::RecordNotUnique
    find_by!(contract_payment_id: payment.id)
  end

  # "SG-0012"
  def display_number
    "#{prefix}-#{number.to_s.rjust(4, '0')}"
  end

  def voided?
    voided_at.present?
  end

  def void!(reason, combined_into: nil)
    return if voided?

    update!(voided_at: Time.current, void_reason: reason, combined_into_payment: combined_into)
  end

  def filename
    "Invoice #{display_number}.pdf"
  end

  # Where it stands, for the page, the PDF and the lists.
  def state
    payment = contract_payment
    return :void if voided? || payment.nil? || payment.status_cancelled?
    return :paid if payment.status_paid?

    payment.overdue? ? :overdue : :due
  end

  # The invoice itself, as the page and the PDF show it. The PDF also prints
  # the pay link (the page has the button).
  def document(pdf: false)
    payment = contract_payment
    contract = payment.contract
    InvoiceDocument.new(
      number: display_number,
      issued_on: issued_at.to_date,
      due_on: state.in?(%i[due overdue]) ? payment.due_date : nil,
      seller: organization.invoice_seller,
      bill_to: InvoiceDocument::Party.new(name: contract.contractor_name, lines: contract.contractor_address.to_s.split(/\r?\n/).map(&:strip),
                                          email: contract.contractor_email, phone: contract.contractor_phone),
      reference: reference(payment, contract),
      items: items(payment),
      total_cents: payment.amount_cents,
      status: state,
      status_line: status_line(payment),
      notes: notes(payment, contract, pdf: pdf),
      footer: "Online payments are processed by #{CocoScoutIdentity::BRAND} (#{CocoScoutIdentity::LEGAL_NAME}) for #{organization.name}.",
      logo: organization.logo
    )
  end

  # "Paid October 3, 2026 · Check #1042"
  def status_line(payment = contract_payment)
    money = ActiveSupport::NumberHelper.number_to_currency(payment.amount.to_f)
    case state
    when :void
      [ "Void", void_reason ].compact_blank.join(": ")
    when :paid
      via = payment.received_via_label
      reference = payment.reference_number.presence if payment.paid_offline?
      [ "Paid#{" #{payment.paid_date.strftime('%B %-d, %Y')}" if payment.paid_date}", via, reference && "##{reference}" ].compact.join(" · ")
    when :overdue
      "Amount due: #{money}, was due #{payment.due_date.strftime('%B %-d, %Y')}"
    else
      "Amount due: #{money} by #{payment.due_date.strftime('%B %-d, %Y')}"
    end
  end

  private

  def reference(payment, contract)
    production = contract.production_name.presence || contract.production&.name
    show = payment.show
    [
      [ "Production", production ],
      [ "Event", show && "#{show.display_name}, #{show.date_and_time.strftime('%a %b %-d, %Y, %-l:%M %p')}" ],
      [ "Venue", show&.location&.name ]
    ]
  end

  # Its own fee, then everything folded or combined into it, each dated.
  def items(payment)
    rows = payment.breakdown_items.presence || [ [ payment.display_name, payment.amount.to_f ] ]
    rows.map { |label, amount| InvoiceDocument::Line.new(description: label, amount_cents: (amount.to_f * 100).round) }
  end

  def notes(payment, contract, pdf:)
    note = organization.invoice_details_with_defaults["note"]
    return [ note ] unless state.in?(%i[due overdue])

    other = contract.offline_payment_methods_sentence
    return [ other && "You can also pay by #{other}.", note ] unless pdf

    url_options = Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
    pay = payment.collectable_online? ? "Pay online: #{Rails.application.routes.url_helpers.pay_contract_url(token: payment.payment_token!, **url_options)}" : nil
    [ pay, other && "You can also pay by #{other}.", note ]
  end
end

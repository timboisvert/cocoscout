# frozen_string_literal: true

class Invoice
  # What the invoice for a contract payment says. The payment keeps the
  # money: what's due, when, from whom and whether it's paid are read from
  # it every time, so the invoice can never disagree with the payment.
  class ContractTerms
    # How it was paid, in a sentence: "on October 3 (by check)".
    PAID_VIA = {
      "online" => "online", "cash" => "in cash", "check" => "by check", "zelle" => "by Zelle",
      "venmo" => "by Venmo", "bank_transfer" => "by bank transfer"
    }.freeze

    def initialize(invoice)
      @invoice = invoice
      @payment = invoice.contract_payment
      @contract = @payment&.contract
      @organization = invoice.organization
    end

    # --- What it says ---------------------------------------------------------

    # A payment that was removed or cancelled leaves its invoice void.
    def state
      return :void if @invoice.void? || @payment.nil? || @payment.status_cancelled?
      return :paid if @payment.status_paid?

      @payment.overdue? ? :overdue : :due
    end

    def paid? = @payment&.status_paid? == true
    def due_on = @payment.due_date
    def total_cents = @payment.amount_cents
    def amount_due_cents = @payment.amount_cents

    # "Paid October 3, 2026 · Check · #1042"
    def paid_line
      via = @payment.received_via_label
      reference = @payment.reference_number.presence if @payment.paid_offline?
      [ "Paid#{" #{@payment.paid_date.strftime('%B %-d, %Y')}" if @payment.paid_date}", via, reference && "##{reference}" ].compact.join(" · ")
    end

    def bill_to
      InvoiceDocument::Party.new(name: @contract.contractor_name, lines: @contract.contractor_address.to_s.split(/\r?\n/).map(&:strip),
                                 email: @contract.contractor_email, phone: @contract.contractor_phone)
    end

    def reference
      show = @payment.show
      [
        [ "Production", @contract.production_name.presence || @contract.production&.name ],
        [ "Event", show && "#{show.display_name}, #{show.date_and_time.strftime('%a %b %-d, %Y, %-l:%M %p')}" ],
        [ "Venue", show&.location&.name ]
      ]
    end

    # Its own fee, then everything folded or combined into it, each dated.
    def items
      rows = @payment.breakdown_items.presence || [ [ @payment.display_name, @payment.amount.to_f ] ]
      rows.map { |label, amount| InvoiceDocument::Line.new(description: label, amount_cents: (amount.to_f * 100).round) }
    end

    # The PDF also prints the pay link (the page has the button).
    def notes(pdf:)
      note = @organization.invoice_details_with_defaults["note"]
      return [ note ] unless state.in?(%i[due overdue])

      other = @contract.offline_payment_methods_sentence
      return [ other && "You can also pay by #{other}.", note ] unless pdf

      [ (@payment.collectable_online? ? "Pay online: #{page_url}" : nil), other && "You can also pay by #{other}.", note ]
    end

    # --- Sending it -----------------------------------------------------------

    TEMPLATES = { invoice: "contract_invoice", reminder: "contract_invoice_reminder", receipt: "contract_payment_receipt" }.freeze

    def template(which) = TEMPLATES.fetch(which)

    # The email on the contract, else the contractor's own.
    def recipient_email = @contract.contractor_email.presence || @contract.contractor&.email.presence
    def payer_name = @contract.contractor_name.presence || "there"
    def description = @payment.display_name
    def page_url = routes.pay_contract_url(token: @payment.payment_token!, **link_options)
    def pdf_url = routes.pay_contract_invoice_url(token: @payment.payment_token!, format: :pdf, **link_options)
    def production = @contract.production
    # A payer with a CocoScout account gets the same words as a message.
    def inbox_person = @contract.signer_member_person

    def invoice_variables(note)
      { due_date: due_on.strftime("%B %-d, %Y"), custom_message: note.to_s.strip, other_payment_methods: @contract.offline_payment_methods_sentence.to_s }
    end

    def receipt_variables
      { paid_on: (@payment.paid_date || Date.current).strftime("%B %-d, %Y"), paid_via: PAID_VIA[@payment.payment_method].to_s }
    end

    private

    def routes = Rails.application.routes.url_helpers
    def link_options = Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end
end

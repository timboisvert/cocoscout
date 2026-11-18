# frozen_string_literal: true

class Invoice
  # What an invoice the organization wrote says: its own lines, its own due
  # date, and the payments recorded against it.
  class OwnTerms
    PAID_VIA = ContractTerms::PAID_VIA

    def initialize(invoice)
      @invoice = invoice
      @organization = invoice.organization
    end

    # --- What it says ---------------------------------------------------------

    def state = @invoice.void? ? :void : (@invoice.paid? ? :paid : (@invoice.overdue? ? :overdue : :due))
    def paid? = @invoice.paid?
    def due_on = @invoice.due_on
    def total_cents = @invoice.total_cents
    def amount_due_cents = @invoice.unpaid_cents
    def paid_line = "Paid#{" #{@invoice.paid_on.strftime('%B %-d, %Y')}" if @invoice.paid_on}"

    def bill_to
      InvoiceDocument::Party.new(name: @invoice.bill_to_name,
                                 lines: [ @invoice.bill_to_attention.presence && "Attn. #{@invoice.bill_to_attention}", *@invoice.bill_to_address.to_s.split(/\r?\n/).map(&:strip) ].compact,
                                 email: @invoice.bill_to_email)
    end

    def reference
      show = @invoice.show
      [ [ "Production", @invoice.production&.name ], [ "Event", show && "#{show.display_name}, #{show.date_and_time.strftime('%a %b %-d, %Y')}" ] ]
    end

    def items
      @invoice.invoice_lines.map do |line|
        detail = line.quantity != 1 ? "#{line.quantity_label} × #{ActiveSupport::NumberHelper.number_to_currency(line.unit_cents / 100.0)}" : nil
        InvoiceDocument::Line.new(description: line.description, detail: detail, amount_cents: line.amount_cents)
      end
    end

    # The PDF also prints the pay link (the page has the button).
    def notes(pdf:)
      note = @organization.invoice_details_with_defaults["note"]
      memo = @invoice.memo.presence
      return [ memo, note ].compact_blank unless state.in?(%i[due overdue])

      seller = @organization.invoice_seller
      check = @invoice.pay_by_check ? "You can also pay by check to #{seller.name}#{seller.lines.any? ? ", #{seller.lines.join(', ')}" : ''}." : nil
      return [ memo, check, note ].compact_blank unless pdf

      [ memo, (@invoice.collectable_online? ? "Pay online: #{page_url}" : nil), check, note ].compact_blank
    end

    # --- Sending it -----------------------------------------------------------

    TEMPLATES = { invoice: "invoice", reminder: "invoice_reminder", receipt: "invoice_receipt" }.freeze

    def template(which) = TEMPLATES.fetch(which)
    def recipient_email = @invoice.bill_to_email
    def payer_name = @invoice.bill_to_attention.presence || @invoice.bill_to_name
    def description = @invoice.invoice_lines.first&.description.to_s
    def page_url = routes.pay_invoice_url(token: @invoice.payment_token!, **link_options)
    def pdf_url = routes.pay_invoice_pdf_url(token: @invoice.payment_token!, format: :pdf, **link_options)
    def production = @invoice.production
    # Whoever it's billed to is an address, not an account here.
    def inbox_person = nil

    # The message on the invoice is its own memo; nothing is typed at send.
    def invoice_variables(_note)
      { due_date: due_on.strftime("%B %-d, %Y"), custom_message: @invoice.memo.to_s.strip, ways_to_pay: @invoice.ways_to_pay }
    end

    def receipt_variables
      last = @invoice.invoice_payments.order(:on, :id).last
      { paid_on: (@invoice.paid_on || Date.current).strftime("%B %-d, %Y"), paid_via: PAID_VIA[last&.via].to_s }
    end

    private

    def routes = Rails.application.routes.url_helpers
    def link_options = Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end
end

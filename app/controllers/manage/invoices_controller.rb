# frozen_string_literal: true

module Manage
  # Invoices to anyone (plan D2): the form, an invoice's page, send and
  # remind, record a payment that came by hand, cancel. Listed with
  # everything else owed to you on Incoming Payments.
  class InvoicesController < Manage::ManageController
    before_action :set_invoice, only: %i[show pdf send_invoice record_payment void]
    before_action :require_change!, only: %i[new create send_invoice record_payment void]
    before_action :load_choices, only: %i[new create]

    def new
      @invoice = Current.organization.invoices.new(issued_on: Date.current, due_on: Date.current + 15, category_key: "sponsorship")
      @invoice.invoice_lines.build(quantity: 1)
    end

    def create
      @invoice = Current.organization.invoices.new(invoice_params.merge(created_by: Current.user, issued_on: Date.current))
      if @invoice.save
        to = params[:send_now] == "1" ? InvoiceDelivery.send_invoice!(@invoice, sender: Current.user) : nil
        redirect_to manage_money_invoice_path(@invoice), notice: (to ? "Invoice #{@invoice.display_number} sent to #{to}." : "Invoice #{@invoice.display_number} is ready. Send it when you like.")
      else
        @invoice.invoice_lines.build(quantity: 1) if @invoice.invoice_lines.empty?
        render :new, status: :unprocessable_content
      end
    end

    def show
      @payments = @invoice.invoice_payments.order(:on, :id)
      @document = @invoice.document
    end

    def pdf
      send_data InvoicePdf.new(@invoice.document(pdf: true)).render, filename: @invoice.filename, type: "application/pdf", disposition: "inline"
    end

    def send_invoice
      return redirect_to manage_money_invoice_path(@invoice), alert: "This invoice is #{@invoice.status}." unless @invoice.open?

      to = InvoiceDelivery.send_invoice!(@invoice, sender: Current.user)
      if to
        redirect_to manage_money_invoice_path(@invoice), notice: "#{@invoice.sent_count > 1 ? 'Reminder about invoice' : 'Invoice'} #{@invoice.display_number} sent to #{to}."
      else
        redirect_to manage_money_invoice_path(@invoice), alert: "There is no email address to send it to. Copy the link instead."
      end
    end

    def record_payment
      return redirect_to manage_money_invoice_path(@invoice), alert: "This invoice is #{@invoice.status}." unless @invoice.open?

      cents = (params[:amount].to_s.delete("$,").to_f * 100).round
      cents = @invoice.unpaid_cents if cents <= 0
      on = Date.parse(params[:on].presence || Date.current.iso8601) rescue Date.current
      @invoice.receive!(on: on, amount_cents: cents, via: params[:via].presence_in(InvoicePayment::VIA.keys - [ "online" ]) || "check", by: Current.user,
                        reference: params[:reference].presence, memo: params[:memo].presence)
      InvoiceDelivery.send_receipt!(@invoice) if @invoice.reload.paid?
      redirect_to manage_money_invoice_path(@invoice), notice: (@invoice.paid? ? "Paid in full. Invoice #{@invoice.display_number} is settled." : "#{helpers.number_to_currency(cents / 100.0)} recorded; #{helpers.number_to_currency(@invoice.unpaid_cents / 100.0)} still owed.")
    end

    def void
      @invoice.void!(params[:reason])
      redirect_to manage_money_incoming_path, notice: "Invoice #{@invoice.display_number} is cancelled. The number stays used; send a new one."
    end

    private

    def set_invoice
      @invoice = Current.organization.invoices.find(params[:id])
    end

    def require_change!
      return if OrganizationAccess.allows?(Current.user, Current.organization, :bills_invoices, :manage)

      redirect_to manage_money_incoming_path, alert: "You can look at invoices but not change them."
    end

    def load_choices
      @productions = Current.organization.productions.active.order(:name)
      @shows = Show.where(production_id: @productions.map(&:id), canceled: false).order(date_and_time: :desc).limit(400).select(:id, :production_id, :date_and_time, :secondary_name)
    end

    def invoice_params
      params.require(:invoice).permit(:bill_to_name, :bill_to_email, :bill_to_attention, :bill_to_address, :due_on, :category_key, :production_id, :show_id, :memo,
                                      :pay_by_card, :pay_by_bank, :pay_by_check, :reminders,
                                      invoice_lines_attributes: %i[id description quantity unit _destroy])
    end
  end
end

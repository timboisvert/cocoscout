# frozen_string_literal: true

# One invoice, as both its web page and its PDF (InvoicePdf) render it, so the
# two can never disagree. Built by ContractInvoice#document (money someone owes
# an organization) and CocoScoutInvoice.document (what CocoScout billed an
# organization).
class InvoiceDocument
  # Who it's from or to: a name, address lines, email and phone.
  Party = Data.define(:name, :lines, :email, :phone) do
    def initialize(name:, lines: [], email: nil, phone: nil)
      super(name: name.to_s, lines: Array(lines).compact_blank, email: email.presence, phone: phone.presence)
    end
  end

  # One line of what's owed: "Rent — Oct 10, 2026", an optional detail under
  # it, and its amount.
  Line = Data.define(:description, :detail, :amount_cents) do
    def initialize(description:, amount_cents:, detail: nil)
      super(description: description.to_s, detail: detail.presence, amount_cents: amount_cents.to_i)
    end
  end

  # :due, :overdue, :paid, :void, :collecting, :failed
  STAMPS = { paid: "PAID", void: "VOID" }.freeze

  attr_reader :title, :number, :issued_on, :due_on, :seller, :bill_to, :reference, :items,
              :total_cents, :status, :status_line, :notes, :sections, :footer, :logo

  # logo: a PNG path (String/Pathname) or an ActiveStorage attachment.
  # sections: extra lists after the notes, as [[title, [lines]]] (the people
  # a usage bill counted).
  def initialize(number:, issued_on:, seller:, bill_to:, items:, total_cents:, status:, status_line:,
                 title: "Invoice", due_on: nil, reference: [], notes: [], sections: [], footer: nil, logo: nil)
    @title = title
    @number = number
    @issued_on = issued_on
    @due_on = due_on
    @seller = seller
    @bill_to = bill_to
    @reference = Array(reference).reject { |_, value| value.blank? }
    @items = items
    @total_cents = total_cents.to_i
    @status = status
    @status_line = status_line
    @notes = Array(notes).compact_blank
    @sections = Array(sections).reject { |_, lines| lines.blank? }
    @footer = footer
    @logo = logo
  end

  def stamp
    STAMPS[status]
  end

  def paid?
    status == :paid
  end

  def void?
    status == :void
  end
end

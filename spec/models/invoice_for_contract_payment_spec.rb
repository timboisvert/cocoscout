# frozen_string_literal: true

require "rails_helper"

# One invoice per payment someone owes an organization (Tim, 2026-10-05),
# numbered in order per organization, never reused. A combined payment is one
# invoice listing what it combines; the payments it absorbed are void. Since
# 2026-11-09 it is a row in invoices (kind "contract") beside the invoices an
# organization writes to anyone: one table, one sequence, one way to send.
RSpec.describe Invoice, "for a contract payment" do
  let(:org) { create(:organization, name: "Stars & Garters") }
  let(:contract) { create(:contract, :active, organization: org, contractor_name: "Gigi Noble Wolf", contractor_email: "gigi@example.com", production_name: "Funhouse") }

  def owed(description, amount, due: Date.current + 7)
    create(:contract_payment, contract: contract, direction: "incoming", amount: amount, amount_tbd: false,
                              due_date: due, description: description, settlement_method: "direct")
  end

  # Prawn writes text as hex strings; this reads them back.
  def pdf_text(bytes)
    bytes.scan(/<([0-9a-fA-F]+)>/).flatten.map { |hex| [ hex ].pack("H*") }.join
  end

  it "numbers invoices in order per organization, each starting at 0001, from the organization's initials" do
    first = described_class.for!(owed("Rent", 300))
    second = described_class.for!(owed("Deposit", 100))
    other_org = create(:organization, name: "Laugh Along Live")
    elsewhere = described_class.for!(create(:contract_payment, contract: create(:contract, :active, organization: other_org),
                                                               direction: "incoming", amount: 50, amount_tbd: false))

    expect([ first.display_number, second.display_number ]).to eq(%w[SG-0001 SG-0002])
    expect(elsewhere.display_number).to eq("LAL-0001")
  end

  it "gives a payment the same invoice every time it's opened" do
    payment = owed("Rent", 300)
    expect(described_class.for!(payment)).to eq(described_class.for!(payment.reload))
    expect(org.reload.invoice_next_number).to eq(2)
  end

  it "keeps an issued number when the prefix changes, and uses the new prefix after" do
    first = described_class.for!(owed("Rent", 300))
    org.update!(invoice_prefix: "sng")
    second = described_class.for!(owed("Deposit", 100))

    expect([ first.reload.display_number, second.display_number ]).to eq(%w[SG-0001 SNG-0002])
  end

  it "lists what a combined payment covers, and voids the invoices of the payments it absorbed" do
    host = owed("Rent", 300)
    absorbed = owed("Booth tech", 50, due: Date.current + 3)
    absorbed_invoice = described_class.for!(absorbed)

    host.merge_in!([ absorbed ])

    host_invoice = host.reload.invoice
    expect(absorbed_invoice.reload).to be_void
    expect(absorbed_invoice.void_reason).to eq("Combined into #{host_invoice.display_number}")
    expect(absorbed_invoice.combined_into_payment).to eq(host)
    expect(host_invoice.document.items.map(&:amount_cents)).to eq([ 30_000, 5_000 ])
    expect(host_invoice.document.total_cents).to eq(35_000)
  end

  it "voids the invoice of a payment that's removed or cancelled, and never reuses its number" do
    removed = owed("Rent", 300)
    invoice = described_class.for!(removed)
    removed.destroy!
    expect(invoice.reload).to be_void
    expect(invoice.contract_payment_id).to be_nil
    expect(invoice.state).to eq(:void)

    cancelled = owed("Deposit", 100)
    cancelled_invoice = described_class.for!(cancelled)
    cancelled.update!(status: "cancelled")
    expect(cancelled_invoice.reload.state).to eq(:void)
    expect(described_class.for!(owed("Tech", 25)).display_number).to eq("SG-0003")
  end

  it "makes a PDF that says what's due, and PAID with the date and method once it's paid" do
    payment = owed("Rent", 300)
    invoice = described_class.for!(payment)

    due = pdf_text(InvoicePdf.new(invoice.document(pdf: true)).render)
    expect(due).to include("SG-0001", "Gigi Noble Wolf", "Funhouse", "Amount due: $300.00")
    expect(due).not_to include("PAID")

    payment.mark_paid!(paid_on: Date.new(2026, 10, 3), method: "bank_transfer", reference: "1042")
    paid = pdf_text(InvoicePdf.new(invoice.reload.document(pdf: true)).render)
    expect(paid).to include("PAID", "Paid October 3, 2026", "Bank transfer", "#1042")
  end

  it "shares one sequence and one table with the invoices the organization writes, and stays out of their lists and books" do
    first = described_class.for!(owed("Rent", 300))
    written = org.invoices.new(bill_to_name: "Lincoln Park High School", issued_on: Date.current, due_on: Date.current + 15, category_key: "sponsorship")
    written.invoice_lines.build(description: "Program ad", quantity: 1, unit_cents: 12_000)
    written.save!
    third = described_class.for!(owed("Deposit", 100))

    expect([ first, written, third ].map(&:display_number)).to eq(%w[SG-0001 SG-0002 SG-0003])
    expect([ first, written, third ].map(&:kind)).to eq(%w[contract standalone contract])
    # The database itself refuses a number used twice, whichever kind.
    expect { described_class.transaction(requires_new: true) { described_class.where(id: third.id).update_all(number: 2) } }.to raise_error(ActiveRecord::RecordNotUnique)

    # The organization's invoices are the ones it wrote; a payment's invoice
    # is reached through its payment.
    expect(org.invoices.to_a).to eq([ written ])
    expect(org.contract_invoices.order(:number).to_a).to eq([ first, third ])
    # Its money is the payment's: nothing of its own on the books, no lines, no due date of its own.
    expect(JournalEntry.where(source: [ first, third ])).to be_empty
    expect(JournalEntry.live.where(source: written).pluck(:kind)).to eq([ "invoice" ])
    expect(first.due_on).to be_nil
    expect(first.terms.due_on).to eq(first.contract_payment.due_date)
    expect(first.terms.total_cents).to eq(30_000)
    expect(first.state).to eq(:due)

    # A pay link for one kind never opens the other's page.
    expect(described_class.standalone.find_by(payment_token: first.payment_token)).to be_nil
  end

  it "names a bank transfer when one was recorded" do
    payment = owed("Rent", 300)
    payment.mark_paid!(method: "bank_transfer")
    expect(payment.offline_payment_method_label).to eq("Bank transfer")
  end

  it "doesn't invoice money netted out of a payout, an amount still to come, or money we owe" do
    expect(owed("Rent", 300)).to be_invoiceable
    expect(create(:contract_payment, contract: contract, direction: "incoming", amount: 0, amount_tbd: true)).not_to be_invoiceable
    expect(create(:contract_payment, contract: contract, direction: "outgoing", amount: 200, amount_tbd: false)).not_to be_invoiceable
  end

  it "fills the invoice from the organization's invoice settings over what CocoScout knows" do
    org.update!(invoice_details: { "address" => "1714 S. Desplaines St.\nChicago, IL 60616", "note" => "Make checks payable to S&G LLC." })
    document = described_class.for!(owed("Rent", 300)).document

    expect(document.seller.name).to eq("Stars & Garters")
    expect(document.seller.lines).to eq([ "1714 S. Desplaines St.", "Chicago, IL 60616" ])
    expect(document.seller.email).to eq(org.owner.email_address)
    expect(document.notes).to include("Make checks payable to S&G LLC.")
  end
end

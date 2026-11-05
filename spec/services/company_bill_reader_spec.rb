# frozen_string_literal: true

require "rails_helper"

# Bills uploaded to superadmin Finances' Costs page are read off the PDF:
# an Amazon invoice gives its number, total, month and services; an
# Anthropic receipt its number, the amount paid and the day.
RSpec.describe CompanyBillReader do
  let(:amazon) do
    <<~TEXT
      Amazon Web Services Invoice
      Email or talk to us about your AWS account or bill, visit aws.amazon.com/contact-us/
      Invoice Summary
      Invoice Number: 1987654321
      Invoice Date: February 2 , 2026
      TOTAL AMOUNT DUE ON February 2 , 2026 $1,284.37
      Account number: 123456789012
      This invoice is for the billing period January 1 - January 31 , 2026
      Summary
      AWS Service Charges $1,284.37
      Charges $1,201.10
      Credits $0.00
      Tax $83.27
      Total for this invoice $1,284.37
      Detail
      Amazon Elastic Compute Cloud $640.12
      Charges $640.12
      Tax $0.00
      Amazon Relational Database Service $410.98
      Charges $410.98
      Amazon Simple Storage Service $150.00
      Charges $150.00
      Credits -$12.00
    TEXT
  end

  let(:anthropic) do
    <<~TEXT
      Receipt
      Invoice number 7C2D91AF-0004
      Receipt number 2069-5479-2866
      Date paid October 20, 2026
      Payment method Visa - 4242
      Anthropic, PBC
      $181.18 paid on October 20, 2026
      Description Qty Unit price Amount
      Max plan - 20x Oct 20 - Nov 20, 2026 1 $157.55 $157.55
      Subtotal $157.55
      Total $181.18
      Amount paid $181.18
    TEXT
  end

  it "reads an Amazon invoice: its number, total, the month it's for, and each service" do
    result = described_class.from_text(amazon)
    expect(result).to be_complete
    expect(result.attributes).to include(vendor: "Amazon", category: "hosting", bill_number: "1987654321", bill_total_cents: 128_437,
                                         period_month: Date.new(2026, 1, 1), billed_on: Date.new(2026, 2, 2))
    expect(result.attributes[:breakdown]).to eq([ [ "Amazon Elastic Compute Cloud", 64_012 ], [ "Amazon Relational Database Service", 41_098 ],
                                                  [ "Amazon Simple Storage Service", 15_000 ] ])
  end

  it "reads an Anthropic receipt: the receipt number, what was paid, and the day" do
    result = described_class.from_text(anthropic)
    expect(result).to be_complete
    expect(result.attributes).to include(vendor: "Anthropic", category: "software", bill_number: "2069-5479-2866", bill_total_cents: 18_118,
                                         period_month: Date.new(2026, 10, 1), paid_on: Date.new(2026, 10, 20))
  end

  it "reads a GitHub receipt for Copilot, whichever way it writes the date" do
    receipt = <<~TEXT
      GitHub
      We received payment for your GitHub.com subscription. Thanks for your business!
      GITHUB RECEIPT - PERSONAL SUBSCRIPTION - timboisvert
      Copilot Pro - Month
      Subtotal: $10.00 USD
      Total: $10.70 USD*
      Charged to: Visa (4*** **** **** 4242)
      Transaction ID: 6XK29ALQ
      Date: 15 Mar 2026 10:23AM PST
      For service through: 2026-04-14
    TEXT
    result = described_class.from_text(receipt)
    expect(result).to be_complete
    expect(result.attributes).to include(vendor: "GitHub", category: "software", description: "GitHub Copilot Pro", bill_number: "6XK29ALQ",
                                         bill_total_cents: 1_070, period_month: Date.new(2026, 3, 1), paid_on: Date.new(2026, 3, 15))

    table = "GitHub Receipt\nDate 2026-02-15\nAccount billed timboisvert\nItem GitHub Copilot $10.00\nTotal $10.00 USD\nTransaction ID ch_3Abc9\n"
    expect(described_class.from_text(table).attributes).to include(vendor: "GitHub", description: "GitHub Copilot", bill_number: "ch_3Abc9",
                                                                   bill_total_cents: 1_000, period_month: Date.new(2026, 2, 1))
  end

  it "reads the text out of a real PDF" do
    pdf = Prawn::Document.new { |doc| amazon.each_line { |line| doc.text line.chomp } }.render
    result = described_class.read(StringIO.new(pdf), filename: "invoice.pdf")
    expect(result.attributes).to include(vendor: "Amazon", bill_number: "1987654321", bill_total_cents: 128_437, period_month: Date.new(2026, 1, 1))
  end

  it "leaves an unknown bill for a person to fill in, named for its file" do
    result = described_class.from_text("Thanks for your order.", filename: "apple_developer-2026.pdf")
    expect(result).not_to be_complete
    expect(result.attributes).to include(vendor: "apple developer 2026", category: "other")
    expect(described_class.read(StringIO.new("not a pdf"), filename: "x.pdf")).not_to be_complete
  end
end

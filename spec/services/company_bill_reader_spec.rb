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

  # Amazon's own layout, as its PDFs read: amounts as "USD 139.46", a
  # Savings Plan line under a service, and credits that can pay the lot.
  it "reads Amazon's real layout, and a month its credits paid in full is a real $0" do
    invoice = <<~TEXT
                                           Amazon Web Services, Inc. Invoice
      Account number:
      111122223333                         Invoice Summary
      Bill to Address:                     Invoice Number:                         2896000001
                                           Invoice Date:                    November 1 , 2026
                                           TOTAL AMOUNT DUE ON November 1 , 2026   USD 139.46
      This invoice is for the billing period October 1 - October 31 , 2026
       Summary
         AWS Service Charges                                                USD 139.46
            Charges                                                         USD 171.50
            Savings Plan (Charges covered by Savings Plans)                 -USD 50.00
            Credits                                                           USD 0.00
            Tax                                                              USD 17.96
       Total for this invoice                                               USD 139.46
       Detail
         AWS Key Management Service                                           USD 0.00
            Charges                                                           USD 0.00
         Elastic Load Balancing                                              USD 19.37
            Charges                                                          USD 16.84
            Estimated US sales tax to be collected                            USD 2.53
         Amazon Elastic Compute Cloud                                       USD 120.09
            Charges                                                         USD 154.66
            Savings Plan (Charges covered by Savings Plans)                 -USD 50.00
            Estimated US sales tax to be collected                           USD 15.43
      * May include estimated US sales tax, VAT, ST, GST and CT.
    TEXT
    result = described_class.from_text(invoice)
    expect(result).to be_complete
    expect(result.attributes).to include(bill_number: "2896000001", bill_total_cents: 13_946, period_month: Date.new(2026, 10, 1), billed_on: Date.new(2026, 11, 1))
    expect(result.attributes[:breakdown]).to eq([ [ "Elastic Load Balancing", 1_937 ], [ "Amazon Elastic Compute Cloud", 12_009 ] ])
    expect(result.attributes).not_to have_key(:note)

    free = invoice.gsub("USD 139.46", "USD 0.00").sub("Credits                                                           USD 0.00", "Credits   -USD 117.51")
    result = described_class.from_text(free)
    expect(result).to be_complete
    expect(result.attributes).to include(bill_total_cents: 0, note: "Amazon credits covered $117.51 of this month.")
  end

  it "reads an Anthropic receipt: the receipt number, what was paid, and the day" do
    result = described_class.from_text(anthropic)
    expect(result).to be_complete
    expect(result.attributes).to include(vendor: "Anthropic", category: "development", bill_number: "2069-5479-2866", bill_total_cents: 18_118,
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
    expect(result.attributes).to include(vendor: "GitHub", category: "development", description: "GitHub Copilot Pro", bill_number: "6XK29ALQ",
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

  # Mailgun's invoice (Tim, 2026-11-14): CocoScout's email, paid by Coco
  # Runs Everything. Read from the real November invoice's text.
  describe "a Mailgun invoice" do
    let(:mailgun) do
      <<~TEXT
        Invoice
        Mailgun Technologies, Inc.                                                 Account: CocoScout
        112 E. Pecan St.
                                                                                 Account ID: A00005268
        San Antonio, TX, 78205                                              Invoice Number: INV00010056
        USA                                                                      Issue Date: 11/13/2026
                                                                                  Due Date: 11/13/2026
        Invoice Charges
               Rate Plan             Charge Name             Service Date             Quantity                Amount
          Basic_10k               Subscription Fee -         11/13/2026 -                 1                     $9.00
                                  Mailgun Basic 10k --        11/30/2026
                                  Proration
                                                            Invoice Total
                                                                  Sub total:                                       $9.00 USD
                                                               Subtotal Tax:                                       $1.35 USD
                                                                Grand Total:                                      $10.35 USD
                                                                 Payments:                                      ($10.35) USD
                                                       Invoice Balance Due:                                        $0.00 USD
                                                           Date of Payment:                                        11/13/2026
      TEXT
    end

    it "reads its number, its total with tax, the month, the day paid and the plan" do
      result = described_class.from_text(mailgun)
      expect(result).to be_complete
      expect(result.attributes).to include(
        vendor: "Mailgun", category: "software", description: "Mailgun Basic 10k", bill_number: "INV00010056",
        bill_total_cents: 1_035, period_month: Date.new(2026, 11, 1), billed_on: Date.new(2026, 11, 13),
        paid_on: Date.new(2026, 11, 13), note: "A first month, prorated."
      )
      expect(result.attributes[:breakdown]).to eq([ [ "Mailgun Basic 10k", 900 ], [ "Tax", 135 ] ])
    end
  end
end

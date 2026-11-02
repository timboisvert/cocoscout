# frozen_string_literal: true

require "rails_helper"

# Books → Bank: the statement file read into lines (plan D3). Chase's CSV
# was read wrong on 2026-11-02: its "Details" column (DEBIT, CREDIT) was
# taken for the description, and two identical lines on a day collapsed.
RSpec.describe BankStatementParser do
  it "reads Chase's layout: the Description column, the running balance, and repeats on a day" do
    csv = <<~CSV
      Details,Posting Date,Description,Amount,Type,Balance,Check or Slip #
      DEBIT,10/30/2026,Zelle payment to Jane Doe 123456,-200.00,QUICKPAY_DEBIT,,
      CREDIT,10/29/2026,STRIPE TRANSFER ST-ABC,1500.00,ACH_CREDIT,1400.00,
      DEBIT,10/28/2026,CHICAGO LUMBER CO,-240.00,DEBIT_CARD,-100.00,
      DEBIT,10/28/2026,CHICAGO LUMBER CO,-240.00,DEBIT_CARD,140.00,
    CSV
    result = described_class.parse(csv, filename: "Chase1234_Activity.CSV")
    expect(result.format).to eq("csv")
    expect(result.lines.map { |l| l[:description] }).to eq([ "Zelle payment to Jane Doe 123456", "STRIPE TRANSFER ST-ABC", "CHICAGO LUMBER CO", "CHICAGO LUMBER CO" ])
    expect(result.lines.map { |l| l[:amount_cents] }).to eq([ -20_000, 150_000, -24_000, -24_000 ])
    expect(result.lines.map { |l| l[:seq] }).to eq([ 0, 0, 0, 1 ])
    # The pending row has no balance; the closing balance is the newest row that has one.
    expect(result.closing_balance_cents).to eq(140_000)
    expect(result.closing_on).to eq(Date.new(2026, 10, 29))
    # Before the oldest line the account held its balance less that line.
    expect(result.opening_balance_cents).to eq(38_000)
    expect(result.opening_on).to eq(Date.new(2026, 10, 28))

    first, second = result.lines.last(2)
    expect(BankStatementLine.fingerprint_for(first[:on], first[:amount_cents], first[:description], first[:seq]))
      .not_to eq(BankStatementLine.fingerprint_for(second[:on], second[:amount_cents], second[:description], second[:seq]))
  end

  it "reads an oldest-first file with debit and credit columns and no balance" do
    result = described_class.parse("Date,Description,Debit,Credit\n10/05/2026,CHICAGO LUMBER CO,240.00,\n10/06/2026,LOGAN SQ CHAMBER,,900.00\n")
    expect(result.lines.map { |l| l[:amount_cents] }).to eq([ -24_000, 90_000 ])
    expect(result.closing_balance_cents).to be_nil
  end

  it "keys a description without the bank's noise" do
    expect(BankStatementLine.description_key_for("ORIG CO NAME:HOTTIX LLC ORIG ID:1234567890 DESC DATE:102926 CO ENTRY DESCR:PAYMENTS SEC:CCD TRACE#:021000029876543 EED:261029 IND ID:SG00012"))
      .to eq("HOTTIX LLC DESC DATE PAYMENTS")
    expect(BankStatementLine.description_key_for("CHICAGO LUMBER CO 7781")).to eq(BankStatementLine.description_key_for("CHICAGO LUMBER CO 9920"))
  end
end

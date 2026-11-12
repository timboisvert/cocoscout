# frozen_string_literal: true

require "rails_helper"

# Who a bank line is from or to, read from the bank's own formats (Tim,
# 2026-11-03): the examples are from a real Chase statement.
RSpec.describe BankPayees do
  def read(text) = described_class.read(text)

  it "reads a bank draft's sender, and a payment provider's payout" do
    expect(read("ORIG CO NAME:GUSTO ORIG ID:9138864001 DESC DATE:260727 CO ENTRY DESCR:CND 702045SEC:CCD")).to have_attributes(kind: "draft", name: "Gusto", phrase: "GUSTO")
    expect(read("ORIG CO NAME:STRIPE CO ENTRY DESCR:TRANSFER SEC:CCD IND ID:ST-K4K8A3S5D2Q9")).to have_attributes(kind: "provider", name: "Stripe", phrase: "STRIPE", provider: true)
    expect(read("ORIG CO NAME:Stars & Garters ORIG ID:4270465600 DESC DATE: CO ENTRY DESCR:856e53379cSEC:CCD IND ID:ST-A3E4L4I5E1L2")).to have_attributes(kind: "provider", name: "Stars & Garters", phrase: "Stars & Garters")
    expect(read("ORIG CO NAME:IL DEPT OF REVEN ORIG ID:5555566257 DESC DATE: CO ENTRY DESCR:EDI PYMNTSSEC:CCD")).to have_attributes(name: "IL Dept of Reven", phrase: "IL DEPT OF REVEN")
    expect(read("ORIG CO NAME:ComEd ORIG ID:2360938600 DESC DATE:261001 CO ENTRY DESCR:PAYMENTS IND NAME:Biddle,Christopher")).to have_attributes(name: "ComEd")
  end

  it "reads Zelle names without the reference, online payments, transfers, checks, deposits, withdrawals and fees" do
    expect(read("Zelle payment to Jaki Torres Cleaner JPM99cpv028k")).to have_attributes(kind: "zelle_to", name: "Jaki Torres Cleaner", phrase: "to Jaki Torres Cleaner")
    expect(read("Zelle payment to TIMOTHY BOISVERT 30569942556")).to have_attributes(kind: "zelle_to", name: "Timothy Boisvert", phrase: "to TIMOTHY BOISVERT")
    expect(read("Zelle payment from THE CONSPIRATORS NFP 29628449853")).to have_attributes(kind: "zelle_from", name: "The Conspirators NFP", phrase: "from THE CONSPIRATORS NFP")
    expect(read("Zelle payment from BRETT ASHLEIGH BACxbyclcxkb")).to have_attributes(name: "Brett Ashleigh")
    expect(read("Zelle payment to Joe 30152397238")).to have_attributes(name: "Joe", phrase: "to Joe")
    expect(read("Zelle payment to 3072561606 30152397238")).to have_attributes(name: "3072561606", phrase: "to 3072561606")
    expect(described_class.normalize("3072561606")).not_to eq(described_class.normalize("8152388903"))
    expect(read("Online ACH Payment 11221858791 To DangerCircusThomBritton (_###4785)")).to have_attributes(kind: "online", name: "DangerCircusThomBritton", phrase: "To DangerCircusThomBritton")
    expect(read("Online Payment 27677356683 To FLOOD BROTHERS DISPOSAL CO 01/13")).to have_attributes(kind: "online", name: "Flood Brothers Disposal CO", phrase: "To FLOOD BROTHERS DISPOSAL CO")
    expect(read("Online Transfer from CHK ...5039 transaction#: 31421453923")).to have_attributes(kind: "transfer", name: "Your own accounts", phrase: "Online Transfer")
    expect(read("CHECK 143")).to have_attributes(kind: "check", name: "Checks", phrase: nil)
    expect(read("CHECK 143").rule?).to be(false)
    expect(read("ATM CASH DEPOSIT 08/03 1130 S CANAL ST CHICAGO IL")).to have_attributes(kind: "deposit", phrase: "ATM CASH DEPOSIT")
    expect(read("REMOTE ONLINE DEPOSIT # 1")).to have_attributes(kind: "deposit", phrase: "REMOTE ONLINE DEPOSIT")
    expect(read("DEPOSIT ID NUMBER 95665")).to have_attributes(kind: "deposit", phrase: "DEPOSIT ID NUMBER")
    expect(read("WITHDRAWAL 08/14")).to have_attributes(kind: "withdrawal", phrase: "WITHDRAWAL")
    expect(read("STANDARD ACH PMNTS INITIAL FEE QTY = 2")).to have_attributes(kind: "fee", name: "Bank fees", phrase: "STANDARD ACH PMNTS INITIAL FEE")
  end

  it "reads a card purchase's merchant before the reference, the phone number, the store, the state and the date" do
    expect(read("FACEBK *UDRMRVHTS2 650-5434800 DE 07/02")).to have_attributes(kind: "card", name: "Facebook", phrase: "FACEBK")
    expect(read("FACEBK *AP2GN9M752 fb.me/ads CA 01/12")).to have_attributes(name: "Facebook", phrase: "FACEBK")
    expect(read("AMAZON MKTPL*YM5BN89 Amzn.com/bill WA 06/06")).to have_attributes(name: "Amazon", phrase: "AMAZON MKTPL")
    expect(read("Amazon.com*634K80Y13 Amzn.com/bill WA 06/05")).to have_attributes(name: "Amazon", phrase: "Amazon.com")
    expect(read("THE HOME DEPOT #1950 CHICAGO IL 192195 08/27")).to have_attributes(name: "The Home Depot", phrase: "THE HOME DEPOT")
    expect(read("HOMEDEPOT.COM 800-466-3337 GA 08/15")).to have_attributes(name: "Homedepot.com", phrase: "HOMEDEPOT.COM")
    expect(read("COSTCO WHSE #1107 CHICAGO IL 496142 10/29")).to have_attributes(name: "Costco Whse", phrase: "COSTCO WHSE")
    expect(read("STAPLES 1617 DEBIT CHICAGO IL 484935 05/28")).to have_attributes(name: "Staples", phrase: "STAPLES")
    expect(read("SQ *POP UP KARAOKE gosq.com IL 10/18")).to have_attributes(name: "Pop Up Karaoke", phrase: "SQ *POP UP KARAOKE")
    expect(read("BP#8940397IRVIN CHICAGO IL 08/05")).to have_attributes(name: "BP", phrase: "BP#")
    expect(read("POS DEBIT GOOGLE *WORKSPACE_STAR CC@GOOGLE.CO CA")).to have_attributes(name: "Google", phrase: "GOOGLE")
    expect(read("Spotify P42663A9C5 New York NY 05/13")).to have_attributes(name: "Spotify", phrase: "Spotify")
    expect(read("ASTOUND 800-427-8686 PA 10/19")).to have_attributes(name: "Astound", phrase: "ASTOUND")
  end

  it "groups the lines waiting by payee and direction, most lines first, and offers the look-alikes" do
    org = create(:organization)
    import = org.bank_statement_imports.create!(filename: "y.csv", format: "csv", lines_count: 0)
    mk = ->(on, cents, text) { import.bank_statement_lines.create!(organization: org, on: on, amount_cents: cents, description: text) }
    mk.call(Date.new(2026, 1, 5), -2_500, "FACEBK *A 650-5434800 DE 01/05")
    mk.call(Date.new(2026, 2, 5), -2_500, "FACEBK *B 650-5434800 CA 02/05")
    mk.call(Date.new(2026, 3, 5), -2_500, "FACEBK *C fb.me/ads CA 03/05")
    mk.call(Date.new(2026, 1, 6), -40_000, "Zelle payment to TIMOTHY BOISVERT 1")
    mk.call(Date.new(2026, 2, 6), -40_000, "Zelle payment to TIMOTHY BOISVERT 2")
    mk.call(Date.new(2026, 3, 6), -12_000, "Zelle payment to Tim Boisvert 3")
    mk.call(Date.new(2026, 1, 7), 12_800, "ORIG CO NAME:Stars & Garters ORIG ID:1 IND ID:ST-A")
    mk.call(Date.new(2026, 2, 7), 70_000, "ORIG CO NAME:STRIPE ORIG ID:1 IND ID:ST-B")
    mk.call(Date.new(2026, 2, 8), 70_000, "ORIG CO NAME:STRIPE ORIG ID:1 IND ID:ST-C")
    mk.call(Date.new(2026, 2, 9), -500, "ORIG CO NAME:Power Three Insu ORIG ID:1 IND ID:ST-D")
    mk.call(Date.new(2026, 1, 8), -1_000, "THE HOME DEPOT #1950 CHICAGO IL 1 01/08")
    mk.call(Date.new(2026, 1, 9), -1_000, "HOMEDEPOT.COM 800-466-3337 GA 01/09")

    groups = described_class.groups(org)
    # The Home Depot and HomeDepot.com are one payee: the same letters once "the" and ".com" are dropped.
    expect(groups.map { |g| [ g.name, g.direction, g.count ] }).to eq([
      [ "Facebook", "out", 3 ], [ "Stripe", "in", 2 ], [ "Homedepot.com", "out", 2 ], [ "Timothy Boisvert", "out", 2 ],
      [ "Stars & Garters", "in", 1 ], [ "Power Three Insu", "out", 1 ], [ "Tim Boisvert", "out", 1 ]
    ])
    expect(groups.find { |g| g.name == "Homedepot.com" }.phrases).to eq([ "HOMEDEPOT.COM", "THE HOME DEPOT" ])
    facebook = groups.first
    expect(facebook).to have_attributes(kind: "card", total_cents: 7_500, typical_cents: 2_500, from: Date.new(2026, 1, 5), to: Date.new(2026, 3, 5), steady?: false)
    expect(facebook.spellings).to eq([ [ "FACEBK", 3 ] ])
    expect(described_class.siblings(facebook, groups)).to be_empty
    stripe = groups.find { |g| g.name == "Stripe" }
    expect(stripe.provider).to be(true)
    expect(described_class.siblings(stripe, groups).map(&:name)).to eq([ "Stars & Garters" ])
    expect(groups.find { |g| g.name == "Power Three Insu" }.kind).to eq("draft")
    expect(described_class.siblings(groups.find { |g| g.name == "Timothy Boisvert" }, groups).map(&:name)).to eq([ "Tim Boisvert" ])
  end
end

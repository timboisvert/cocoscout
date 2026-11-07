# frozen_string_literal: true

require "rails_helper"

# Discount codes as a spreadsheet (Tim, 2026-11-07): a Codes tab exports the
# codes it lists and imports a CSV's, the same shape, skipping codes already
# there and reporting lines it can't read.
RSpec.describe DiscountCodeCsv do
  let(:org) { create(:organization, :pro, name: "Stars & Garters") }
  let(:production) { create(:production, organization: org, name: "Stargazers") }
  let(:other) { create(:production, organization: org, name: "Encore") }

  it "exports the columns a manager types, and imports them back onto another production" do
    org.ticket_discount_codes.create!(production: production, code: "friends", kind: "fixed", amount_cents: 500, max_uses: 20, shared_with: "team")
    org.ticket_discount_codes.create!(production: production, code: "cast", kind: "percent", percent: 20)

    csv = described_class.export(org.ticket_discount_codes.where(production: production).order(:code))
    expect(csv.lines.map(&:chomp)).to eq([ "Code,Kind,Amount,Most uses,Shared with", "CAST,% off,20,,Production team and cast", "FRIENDS,$ off,5.00,20,Production team only" ])

    result = described_class.import(organization: org, production: other, text: csv)
    expect(result).to be_ok
    expect(result.summary).to eq("Added 2 codes.")
    friends = org.ticket_discount_codes.find_by(production: other, code: "FRIENDS")
    expect([ friends.kind, friends.amount_cents, friends.max_uses, friends.shared_with ]).to eq([ "fixed", 500, 20, "team" ])
    cast = org.ticket_discount_codes.find_by(production: other, code: "CAST")
    expect([ cast.kind, cast.percent.to_f, cast.shared_with ]).to eq([ "percent", 20.0, "team_and_cast" ])
  end

  it "skips a code already there, reads a bare sheet, and names the line it can't read" do
    org.ticket_discount_codes.create!(production: production, code: "FRIENDS", kind: "fixed", amount_cents: 500)
    text = "code,amount\nfriends,5\nhalf,50%\n,3\n"

    result = described_class.import(organization: org, production: production, text: text)
    expect(result).not_to be_ok
    expect(result.added.map(&:code)).to eq([ "HALF" ])
    expect(result.added.first.kind).to eq("percent")
    expect(result.skipped).to eq([ "FRIENDS" ])
    expect(result.errors).to eq([ "Line 4: code can't be blank." ])
    expect(result.summary).to include("Added HALF.", "Already here, skipped: FRIENDS.", "Line 4")
  end

  it "says when it isn't a spreadsheet with a Code column" do
    expect(described_class.import(organization: org, production: production, text: "FRIENDS 5").errors.first).to include("Code column")
    expect(described_class.import(organization: org, production: production, text: "").added).to be_empty
  end
end

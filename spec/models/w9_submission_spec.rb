# frozen_string_literal: true

require "rails_helper"

RSpec.describe W9Submission, type: :model do
  let(:org) { create(:organization, :pro) }
  let(:person) { create(:person) }

  it "encrypts the TIN at rest and keeps only the last four in the clear" do
    w9 = create(:w9_submission, organization: org, person: person, tin: "123-45-6789")

    raw = described_class.connection.select_value("SELECT tin FROM w9_submissions WHERE id = #{w9.id}")
    expect(raw).not_to include("123456789")
    expect(w9.reload.tin).to eq("123456789")
    expect(w9.tin_last4).to eq("6789")
    expect(w9.masked_tin).to eq("•••-••-6789")
    expect(w9.formatted_tin).to eq("123-45-6789")
  end

  it "formats an EIN as an EIN" do
    w9 = build(:w9_submission, tin_type: "ein", tin: "12-3456789")
    w9.validate
    expect(w9.formatted_tin).to eq("12-3456789")
    expect(w9.masked_tin).to eq("••-•••6789")
  end

  it "requires a 9-digit TIN, a US state and a ZIP" do
    w9 = build(:w9_submission, organization: org, person: person, tin: "1234", state: "ZZ", zip: "abc")
    expect(w9).not_to be_valid
    expect(w9.errors.attribute_names).to include(:tin, :state, :zip)
  end

  it "asks an LLC how it's taxed, and drops that answer for anyone else" do
    llc = build(:w9_submission, organization: org, person: person, tax_classification: "llc", llc_tax_class: nil)
    expect(llc).not_to be_valid
    expect(llc.errors.attribute_names).to include(:llc_tax_class)

    individual = build(:w9_submission, organization: org, person: person, llc_tax_class: "S")
    individual.validate
    expect(individual.llc_tax_class).to be_nil
  end

  it "supersedes the previous W-9 when a new one is submitted" do
    first = create(:w9_submission, organization: org, person: person, signed_at: 1.month.ago)
    second = build(:w9_submission, organization: org, person: person, tin: "987654321")
    second.submit!

    expect(first.reload.superseded_at).to be_present
    expect(described_class.current.where(organization: org, person: person)).to eq([ second ])
  end

  it "renders a substitute W-9 PDF" do
    w9 = create(:w9_submission, organization: org, person: person)
    pdf = Tax::W9Pdf.new(w9)
    expect(pdf.render).to start_with("%PDF")
    expect(pdf.filename).to end_with(".pdf")
  end
end

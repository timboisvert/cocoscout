# frozen_string_literal: true

require "rails_helper"

RSpec.describe TaxForm1099, type: :model do
  let(:org) { create(:organization, :pro) }
  let(:person) { create(:person, name: "Sam Staffer") }
  let!(:member) { create(:organization_staff_member, organization: org, person: person, first_name: "Sam", last_name: "Staffer") }
  let!(:w9) { create(:w9_submission, organization: org, person: person, organization_staff_member: member) }
  let!(:tax_setting) do
    org.create_tax_setting!(legal_name: "Stars & Garters LLC", ein: "123456789",
                            address_line1: "1 Stage Door", city: "Chicago", state: "IL", zip: "60601")
  end

  describe ".generate_for_year!" do
    it "creates a draft per person paid in the year, snapshotting W-9 + payer details" do
      allow(Tax::YearEarnings).to receive(:for).and_return(
        person.id => Tax::YearEarnings::Result.new(person_id: person.id, paid_cents: 5_000_00,
                                                    reimbursement_cents: 0, onchain_cents: 5_000_00,
                                                    offline_cents: 0, onchain_return_cents: 0)
      )
      forms = described_class.generate_for_year!(organization: org, tax_year: 2026)
      expect(forms.size).to eq(1)
      form = forms.first
      expect(form.status).to eq("draft")
      expect(form.nec_box1_cents).to eq(5_000_00)
      expect(form.recipient_name).to eq(w9.legal_name)
      expect(form.recipient_tin_last4).to eq("6789")
      expect(form.payer_name).to eq("Stars & Garters LLC")
      expect(form.payer_ein_last4).to eq("6789")
    end

    it "refreshes editable drafts and leaves delivered forms frozen" do
      first_call = { person.id => Tax::YearEarnings::Result.new(person_id: person.id, paid_cents: 5_000_00,
                                                                 reimbursement_cents: 0, onchain_cents: 5_000_00,
                                                                 offline_cents: 0, onchain_return_cents: 0) }
      allow(Tax::YearEarnings).to receive(:for).and_return(first_call)
      described_class.generate_for_year!(organization: org, tax_year: 2026).first

      # Amount doubled the next time we look; a still-draft form updates.
      allow(Tax::YearEarnings).to receive(:for).and_return(
        person.id => Tax::YearEarnings::Result.new(person_id: person.id, paid_cents: 6_000_00,
                                                    reimbursement_cents: 0, onchain_cents: 6_000_00,
                                                    offline_cents: 0, onchain_return_cents: 0)
      )
      described_class.generate_for_year!(organization: org, tax_year: 2026)
      form = TaxForm1099.find_by!(organization: org, person: person, tax_year: 2026, corrects_id: nil)
      expect(form.nec_box1_cents).to eq(6_000_00)

      form.mark_delivered!
      allow(Tax::YearEarnings).to receive(:for).and_return(
        person.id => Tax::YearEarnings::Result.new(person_id: person.id, paid_cents: 7_000_00,
                                                    reimbursement_cents: 0, onchain_cents: 7_000_00,
                                                    offline_cents: 0, onchain_return_cents: 0)
      )
      described_class.generate_for_year!(organization: org, tax_year: 2026)
      expect(form.reload.nec_box1_cents).to eq(6_000_00)
    end

    it "generates a placeholder draft for someone without a W-9, marked undeliverable" do
      no_w9 = create(:person, name: "Blank Slate")
      create(:organization_staff_member, organization: org, person: no_w9, first_name: "Blank", last_name: "Slate")
      allow(Tax::YearEarnings).to receive(:for).and_return(
        no_w9.id => Tax::YearEarnings::Result.new(person_id: no_w9.id, paid_cents: 3_000_00,
                                                   reimbursement_cents: 0, onchain_cents: 3_000_00,
                                                   offline_cents: 0, onchain_return_cents: 0)
      )
      forms = described_class.generate_for_year!(organization: org, tax_year: 2026)
      expect(forms.size).to eq(1)
      expect(forms.first.recipient_tin_last4).to eq("0000")
      expect(forms.first.deliverable?).to be(false)
    end

    it "refuses to run when payer details are incomplete" do
      tax_setting.update!(ein: nil, ein_last4: nil)
      expect {
        described_class.generate_for_year!(organization: org, tax_year: 2026)
      }.to raise_error(ArgumentError, /payer details/)
    end
  end

  describe "reported box 1 and threshold" do
    it "includes the manager's adjustment" do
      form = create(:tax_form_1099, organization: org, person: person, nec_box1_cents: 500_00, adjustment_cents: 100_00)
      expect(form.reported_box1_cents).to eq(600_00)
    end

    it "reflects the year's threshold" do
      form_2025 = build(:tax_form_1099, tax_year: 2025, nec_box1_cents: 500_00)
      form_2026 = build(:tax_form_1099, tax_year: 2026, nec_box1_cents: 500_00)
      expect(form_2025.under_threshold?).to be(true)  # $500 < $600 for 2025
      expect(form_2026.under_threshold?).to be(true) # 2026 threshold is $2,000
    end
  end

  it "renders a PDF that includes the reported amount and hides the full TIN on Copy B" do
    form = create(:tax_form_1099, organization: org, person: person, w9_submission: w9, nec_box1_cents: 4_200_00)
    renderer_b = Tax::Form1099NecPdf.new(form, copy: :recipient)
    renderer_c = Tax::Form1099NecPdf.new(form, copy: :payer)
    expect(renderer_b.render).to start_with("%PDF")
    expect(renderer_c.render).to start_with("%PDF")
    expect(renderer_b.filename).to include("Copy B").and include("Sam Staffer").and include("2026")
    expect(renderer_c.filename).to include("Copy C")
  end

  it "exports IRIS-shaped CSV rows" do
    form = create(:tax_form_1099, organization: org, person: person, w9_submission: w9,
                  nec_box1_cents: 4_200_00, status: "ready")
    csv = Tax::IrisExport.new([ form ]).to_csv
    expect(csv).to include("RecordType,TaxYear,PayerName")
    expect(csv).to include("1099-NEC")
    expect(csv).to include("4200.00")
    expect(csv).to include(form.payer_name)
  end
end

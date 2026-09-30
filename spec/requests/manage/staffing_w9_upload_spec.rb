# frozen_string_literal: true

require "rails_helper"

# A W-9 the org already has (paper, or another system) can be recorded for a
# staff member — the file plus what a 1099 needs — from the staff page or the
# add-staff wizard, and it then works exactly like one filled in online.
RSpec.describe "Staffing W-9 uploads", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:staffer) { create(:person, name: "Sam Staffer", email: "sam@example.com", user: create(:user)) }
  let!(:member) { create(:organization_staff_member, organization: org, person: staffer, acknowledged_at: 1.week.ago) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def w9_params(**overrides)
    {
      document: fixture_file_upload("test_document.pdf", "application/pdf"),
      legal_name: "Sam Staffer", tax_classification: "individual", tin_type: "ssn", tin: "123-45-6789",
      address_line1: "12 Stage Door", city: "Chicago", state: "IL", zip: "60601", signed_on: "2026-03-02"
    }.merge(overrides)
  end

  describe "from the staff page" do
    it "saves it as their current W-9, uploaded by the manager, and serves the file only through the page" do
      post manage_upload_w9_staffing_tax_path(member, from: "staff"), params: { w9: w9_params(e_delivery: "1") }

      expect(response).to redirect_to(manage_edit_staffing_staff_path(member, anchor: "taxes"))
      w9 = member.reload.current_w9
      expect(w9).to be_uploaded
      expect(w9.uploaded_by).to eq(owner)
      expect(w9.tin_last4).to eq("6789")
      expect(w9.signed_at.to_date).to eq(Date.new(2026, 3, 2))
      expect(w9).to be_e_delivery_consented
      expect(w9.document).to be_attached
      expect(member.w9_status).to eq(:received)

      expect {
        get manage_w9_staffing_tax_path(member)
      }.to change(TaxDocumentAccess, :count).by(1)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body).to eq(file_fixture("test_document.pdf").binread)

      get manage_edit_staffing_staff_path(member)
      expect(response.body).to include("uploaded by")
      expect(response.body).not_to include("rails/active_storage")
    end

    it "replaces an online one, and is replaced in turn" do
      online = create(:w9_submission, organization: org, person: staffer, organization_staff_member: member)

      post manage_upload_w9_staffing_tax_path(member), params: { w9: w9_params }
      expect(online.reload.superseded_at).to be_present
      expect(member.reload.current_w9).to be_uploaded
    end

    it "refuses one without the file or the fields a 1099 needs" do
      post manage_upload_w9_staffing_tax_path(member), params: { w9: w9_params(document: nil, tin: "12") }

      expect(flash[:alert]).to include("Document").and include("Tin")
      expect(member.reload.current_w9).to be_nil
    end

    it "refuses a file that isn't a PDF or an image" do
      post manage_upload_w9_staffing_tax_path(member),
           params: { w9: w9_params(document: Rack::Test::UploadedFile.new(StringIO.new("x"), "text/plain", original_filename: "w9.txt")) }

      expect(flash[:alert]).to include("PDF, JPG or PNG")
    end

    it "won't touch another org's staff member" do
      stranger = create(:organization_staff_member, organization: create(:organization, :pro), person: create(:person))

      post manage_upload_w9_staffing_tax_path(stranger), params: { w9: w9_params }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "in the add-staff wizard" do
    # The staged steps work on the member persisted at the Invite step; the
    # wizard finds it through its cached state.
    before do
      allow_any_instance_of(Manage::Staffing::StaffWizardController).to receive(:require_persisted_member) do |controller|
        controller.instance_variable_set(:@staff_member, member)
      end
    end

    it "offers the Tax info step after Agreement when the org collects W-9s" do
      post manage_save_agreement_staffing_staff_wizard_path
      expect(response).to redirect_to(manage_tax_info_staffing_staff_wizard_path)

      get manage_tax_info_staffing_staff_wizard_path
      expect(response.body).to include("Ask them to fill it out while onboarding")
        .and include("I already have their W-9").and include("They don&#39;t need one")
    end

    it "skips it when the org doesn't collect W-9s" do
      org.create_tax_setting!(w9_required: false)

      post manage_save_agreement_staffing_staff_wizard_path
      expect(response).to redirect_to(manage_send_staffing_staff_wizard_path)
    end

    it "records each choice" do
      post manage_save_tax_info_staffing_staff_wizard_path, params: { w9_choice: "exempt" }
      expect(member.reload).to be_tax_form_exempt
      expect(response).to redirect_to(manage_send_staffing_staff_wizard_path)

      post manage_save_tax_info_staffing_staff_wizard_path, params: { w9_choice: "ask" }
      expect(member.reload).not_to be_tax_form_exempt
      expect(member.needs_w9?).to be(true)

      post manage_save_tax_info_staffing_staff_wizard_path, params: { w9_choice: "upload", w9: w9_params }
      expect(member.reload.current_w9).to be_uploaded
      expect(response).to redirect_to(manage_send_staffing_staff_wizard_path)
    end

    it "keeps what was typed when an upload doesn't save" do
      post manage_save_tax_info_staffing_staff_wizard_path,
           params: { w9_choice: "upload", w9: w9_params(document: nil, city: "Evanston") }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Couldn&#39;t save that W-9").and include('value="Evanston"')
    end
  end

  it "fills a 1099 from an uploaded W-9 like any other" do
    StaffW9Upload.new(staff_member: member, uploaded_by: owner, params: w9_params).save
    org.create_tax_setting!(legal_name: "Stars & Garters LLC", ein: "123456789",
                            address_line1: "1 Stage Door", city: "Chicago", state: "IL", zip: "60601")
    allow(Tax::YearEarnings).to receive(:for).and_return(
      staffer.id => Tax::YearEarnings::Result.new(person_id: staffer.id, paid_cents: 5_000_00,
                                                   reimbursement_cents: 0, onchain_cents: 5_000_00,
                                                   offline_cents: 0, onchain_return_cents: 0)
    )

    form = TaxForm1099.generate_for_year!(organization: org, tax_year: 2026).first
    expect(form.recipient_name).to eq("Sam Staffer")
    expect(form.recipient_tin_last4).to eq("6789")
    expect(form).to be_deliverable
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Staffing::Taxes", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  # Someone who can sign in (so they can fill in a W-9) and someone who can't yet.
  let(:staffer_user) { create(:user) }
  let(:staffer) { create(:person, name: "Sam Staffer", email: "sam@example.com", user: staffer_user) }
  let!(:member) { create(:organization_staff_member, organization: org, person: staffer, acknowledged_at: 1.week.ago) }
  let(:newbie) { create(:person, name: "Nia Newbie", email: "nia@example.com") }
  let!(:unclaimed) { create(:organization_staff_member, organization: org, person: newbie) }

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  before { sign_in(owner) }

  it "keeps viewers out" do
    viewer = create(:user, password: password)
    create(:organization_role, user: viewer, organization: org, company_role: "viewer")
    sign_in(viewer) # replaces the owner's session

    get manage_staffing_taxes_path
    expect(response).to redirect_to(manage_path)
  end

  it "shows where everyone stands" do
    get manage_staffing_taxes_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("What needs doing").and include("Sam Staffer").and include("W-9 needed")
    expect(response.body).to include("Ask everyone missing one")
  end

  it "shows who'll be asked and the draft before anything is sent" do
    get manage_staffing_taxes_path

    modal = response.body[/<div id="request-all-w9s".*?Send requests/m]
    expect(modal).to include("Sending to 1 person").and include("Sam Staffer").and include("sam@example.com")
    expect(modal).to include(%(name="staff_member_ids[]")).and include(%(value="#{member.id}"))
    # Nobody who can't sign in yet; onboarding asks them.
    expect(modal).not_to include("Nia Newbie")
    # One draft for everyone, with the name left for each send to fill in.
    expect(modal).to include("{{first_name}}")
  end

  it "sends the edited draft to the people ticked, each with their own first name" do
    expect {
      post manage_request_w9s_staffing_taxes_path, params: {
        staff_member_ids: [ member.id, unclaimed.id ],
        email_subject: "W-9 for {{first_name}}", email_body: "<p>Hi {{first_name}}, one form please.</p>"
      }
    }.to have_enqueued_mail(StaffTaxFormMailer, :w9_request)
      .with(member, to: "sam@example.com", subject: "W-9 for Sam", body: "<p>Hi Sam, one form please.</p>")

    expect(response).to redirect_to(manage_staffing_taxes_path)
    expect(flash[:notice]).to include("Asked 1 person").and include("Nia Newbie")
    expect(member.reload.w9_requested_at).to be_present
    expect(unclaimed.reload.w9_requested_at).to be_nil
  end

  it "asks nobody when nobody's ticked" do
    expect {
      post manage_request_w9s_staffing_taxes_path, params: { email_subject: "x", email_body: "y" }
    }.not_to have_enqueued_mail(StaffTaxFormMailer, :w9_request)

    expect(flash[:alert]).to eq("Tick at least one person to ask.")
    expect(member.reload.w9_requested_at).to be_nil
  end

  it "asks one person with the manager's edited copy, back to their staff page" do
    expect {
      post manage_request_w9_staffing_tax_path(member, from: "staff"),
           params: { email_subject: "Quick favor", email_body: "<p>Please fill this in</p>" }
    }.to have_enqueued_mail(StaffTaxFormMailer, :w9_request)

    expect(response).to redirect_to(manage_edit_staffing_staff_path(member, anchor: "taxes"))
    expect(member.reload.w9_requested_at).to be_present
  end

  it "serves the signed W-9 as a PDF and logs who opened it" do
    create(:w9_submission, organization: org, person: staffer, organization_staff_member: member)

    expect {
      get manage_w9_staffing_tax_path(member)
    }.to change(TaxDocumentAccess, :count).by(1)
    expect(response.media_type).to eq("application/pdf")
    expect(TaxDocumentAccess.last.user).to eq(owner)
  end

  it "doesn't serve another org's W-9" do
    other_member = create(:organization_staff_member, organization: create(:organization, :pro), person: staffer)
    get manage_w9_staffing_tax_path(other_member)
    expect(response).to have_http_status(:not_found)
  end

  describe "around Staffing" do
    it "adds the Taxes tile and W-9 pills to the staffing hub" do
      get manage_staffing_index_path
      expect(response.body).to include(manage_staffing_taxes_path).and include("W-9 needed")
    end

    it "adds a Taxes tab to the staff page, and its exempt toggle lands back on it" do
      get manage_edit_staffing_staff_path(member)
      expect(response.body).to include('data-panel="taxes"').and include("Ask for their W-9")

      patch manage_update_staffing_staff_path(member), params: { tax_form_exempt: "1", return_tab: "taxes" }
      expect(response).to redirect_to(manage_edit_staffing_staff_path(member, anchor: "taxes"))
      expect(member.reload.w9_status).to eq(:exempt)
    end

    it "flags people with no W-9 on the Pay People grid" do
      get manage_staffing_pay_path
      expect(response.body).to include("No W-9 on file yet").and include("given you a W-9 yet")
    end
  end

  describe "Tax settings" do
    it "saves payer details and keeps the EIN when the field is left blank" do
      get manage_staffing_settings_section_path(section: "taxes")
      expect(response).to have_http_status(:ok)

      patch manage_staffing_settings_path, params: {
        updating_taxes: "1", w9_required: "1", legal_name: "Stars & Garters LLC", ein: "12-3456789",
        address_line1: "1 Stage Door", city: "Chicago", state: "il", zip: "60601"
      }
      expect(response).to redirect_to(manage_staffing_settings_section_path(section: "taxes"))
      setting = org.reload.tax_setting
      expect(setting.ein).to eq("123456789")
      expect(setting.state).to eq("IL")
      expect(setting).to be_complete

      patch manage_staffing_settings_path, params: { updating_taxes: "1", w9_required: "1", legal_name: "Stars & Garters LLC", ein: "" }
      expect(org.reload.tax_setting.ein).to eq("123456789")
    end

    it "turns W-9 collection off" do
      patch manage_staffing_settings_path, params: { updating_taxes: "1" }
      expect(org.reload.requires_w9?).to be(false)
      expect(member.reload.needs_w9?).to be(false)
    end

    it "re-renders with errors on a bad EIN" do
      patch manage_staffing_settings_path, params: { updating_taxes: "1", w9_required: "1", ein: "123" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("must be 9 digits")
    end
  end

  describe "1099-NECs" do
    let!(:tax_setting) do
      org.create_tax_setting!(legal_name: "Stars & Garters LLC", ein: "123456789",
                              address_line1: "1 Stage Door", city: "Chicago", state: "IL", zip: "60601")
    end
    let!(:signed_w9) { create(:w9_submission, organization: org, person: staffer, organization_staff_member: member) }

    def stub_earnings(cents_by_person)
      results = cents_by_person.transform_values do |cents|
        Tax::YearEarnings::Result.new(person_id: nil, paid_cents: cents, reimbursement_cents: 0,
                                       onchain_cents: cents, offline_cents: 0, onchain_return_cents: 0)
      end.each_with_index { |(id, r), _| r[:person_id] = id }
      allow(Tax::YearEarnings).to receive(:for).and_return(cents_by_person.each_with_object({}) do |(id, cents), h|
        h[id] = Tax::YearEarnings::Result.new(person_id: id, paid_cents: cents, reimbursement_cents: 0,
                                               onchain_cents: cents, offline_cents: 0, onchain_return_cents: 0)
      end)
    end

    it "shows the 1099 section on the Taxes page with a year switcher" do
      stub_earnings(staffer.id => 3_000_00)
      get manage_staffing_taxes_path(tax_year: 2026)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1099-NEC").and include("Tax year 2026").and include("Sam Staffer")
    end

    it "generates 1099 drafts for people paid in the year" do
      stub_earnings(staffer.id => 5_000_00)
      expect {
        post manage_generate_1099s_staffing_taxes_path, params: { tax_year: 2026 }
      }.to change { org.tax_form_1099s.count }.by(1)
      expect(response).to redirect_to(manage_staffing_taxes_path(tax_year: 2026))
      form = org.tax_form_1099s.first
      expect(form.status).to eq("draft")
      expect(form.nec_box1_cents).to eq(5_000_00)
    end

    it "refuses to generate without payer details" do
      tax_setting.update!(ein: nil, ein_last4: nil)
      stub_earnings(staffer.id => 5_000_00)
      post manage_generate_1099s_staffing_taxes_path, params: { tax_year: 2026 }
      expect(response).to redirect_to(manage_staffing_settings_section_path(section: "taxes"))
      expect(flash[:alert]).to match(/payer details/i)
    end

    it "edits the adjustment and marks it ready" do
      form = create(:tax_form_1099, organization: org, person: staffer, w9_submission: signed_w9,
                    nec_box1_cents: 4_000_00, tax_year: 2026)
      patch manage_update_1099_staffing_tax_path(form),
            params: { adjustment_dollars: "500", adjustment_note: "Cash bonus", federal_withheld_dollars: "0", mark_ready: "1" }
      form.reload
      expect(form.adjustment_cents).to eq(500_00)
      expect(form.adjustment_note).to eq("Cash bonus")
      expect(form.status).to eq("ready")
    end

    it "won't edit a delivered 1099 — a correction is needed" do
      form = create(:tax_form_1099, organization: org, person: staffer, w9_submission: signed_w9,
                    status: "delivered", delivered_at: 1.day.ago, tax_year: 2026)
      patch manage_update_1099_staffing_tax_path(form), params: { adjustment_dollars: "100" }
      expect(response).to redirect_to(manage_staffing_taxes_path)
      expect(flash[:alert]).to match(/correction/i)
    end

    it "delivers only when a W-9 is on file" do
      form = create(:tax_form_1099, organization: org, person: staffer, w9_submission: signed_w9,
                    status: "ready", tax_year: 2026, nec_box1_cents: 4_000_00)
      expect { post manage_deliver_1099_staffing_tax_path(form) }
        .to have_enqueued_mail(StaffTaxFormMailer, :form_1099_ready)
      expect(form.reload.status).to eq("delivered")

      # A form with the "no W-9" placeholder is refused.
      no_w9 = create(:tax_form_1099, organization: org, person: staffer, status: "ready", recipient_tin_last4: "0000",
                     w9_submission: nil, tax_year: 2026)
      expect { post manage_deliver_1099_staffing_tax_path(no_w9) }
        .not_to have_enqueued_mail(StaffTaxFormMailer, :form_1099_ready)
    end

    it "correcting a delivered form opens a fresh draft and marks the original corrected" do
      original = create(:tax_form_1099, organization: org, person: staffer, w9_submission: signed_w9,
                        status: "delivered", delivered_at: 1.day.ago, tax_year: 2026)
      expect { post manage_correct_1099_staffing_tax_path(original) }
        .to change { org.tax_form_1099s.count }.by(1)
      expect(original.reload.status).to eq("corrected")
      correction = org.tax_form_1099s.where(corrects_id: original.id).first
      expect(correction.status).to eq("draft")
    end

    it "marks filed with an optional reference" do
      form = create(:tax_form_1099, organization: org, person: staffer, w9_submission: signed_w9,
                    status: "delivered", delivered_at: 1.day.ago, tax_year: 2026)
      post manage_mark_filed_1099_staffing_tax_path(form),
           params: { filing_reference: "IRIS batch 42", filing_notes: "Uploaded" }
      form.reload
      expect(form.status).to eq("filed")
      expect(form.filed_at).to be_present
      expect(form.filing_reference).to eq("IRIS batch 42")
    end

    it "voids a draft" do
      form = create(:tax_form_1099, organization: org, person: staffer, w9_submission: signed_w9, tax_year: 2026)
      delete manage_void_1099_staffing_tax_path(form)
      expect(form.reload.status).to eq("void")
    end

    it "exports an IRIS CSV of ready/delivered/filed forms" do
      create(:tax_form_1099, organization: org, person: staffer, w9_submission: signed_w9,
             status: "ready", tax_year: 2026, nec_box1_cents: 4_000_00)
      get manage_iris_export_staffing_taxes_path(format: :csv, tax_year: 2026)
      expect(response.media_type).to eq("text/csv")
      expect(response.body).to include("1099-NEC").and include("4000.00").and include("Sam Staffer")
    end

    it "won't leak other orgs' forms" do
      other = create(:organization, :pro)
      foreign = create(:tax_form_1099, organization: other, person: staffer, tax_year: 2026)
      get manage_form_1099_staffing_tax_path(foreign)
      expect(response).to have_http_status(:not_found)
    end
  end
end

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

  it "asks everyone missing a W-9, skipping people without an account" do
    expect {
      post manage_request_w9s_staffing_taxes_path, params: { all: 1 }
    }.to have_enqueued_mail(StaffTaxFormMailer, :w9_request)

    expect(response).to redirect_to(manage_staffing_taxes_path)
    expect(flash[:notice]).to include("Asked 1 person").and include("Nia Newbie")
    expect(member.reload.w9_requested_at).to be_present
    expect(unclaimed.reload.w9_requested_at).to be_nil
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
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "My::TaxForms", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user).tap { |p| user.update!(default_person: p) } }
  let!(:org) { create(:organization, :pro) }
  let!(:member) do
    create(:organization_staff_member, organization: org, person: person,
           first_name: "Sam", last_name: "Staffer", acknowledged_at: 1.week.ago, onboarding_state: "invited")
  end

  let(:w9_params) do
    { legal_name: "Sam Staffer", tax_classification: "individual", address_line1: "123 Main St",
      city: "Springfield", state: "IL", zip: "62701", tin_type: "ssn", tin: "123-45-6789",
      signature_name: "Sam Staffer" }
  end

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  it "shows the form prefilled with their name" do
    get my_w9_path(org.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Form W-9").and include('value="Sam Staffer"')
    expect(response.body).to include(W9Submission::CERTIFICATION_INTRO)
  end

  it "records a signed W-9 and returns them to onboarding" do
    expect {
      post my_w9_path(org.id), params: { w9: w9_params, certify: "1", e_delivery_consent: "1", return_to: "onboarding" }
    }.to change(W9Submission, :count).by(1)

    expect(response).to redirect_to(my_onboarding_path(org.id))
    w9 = member.reload.current_w9
    expect(w9.tin).to eq("123456789")
    expect(w9.signed_ip).to be_present
    expect(w9.e_delivery_consented?).to be(true)
    expect(w9.organization_staff_member).to eq(member)
  end

  it "won't take it without the certification box" do
    expect {
      post my_w9_path(org.id), params: { w9: w9_params }
    }.not_to change(W9Submission, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("certify")
  end

  it "shows errors for a bad TIN without echoing it back" do
    post my_w9_path(org.id), params: { w9: w9_params.merge(tin: "12345"), certify: "1" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("must be 9 digits")
    expect(response.body).not_to include('value="12345"')
  end

  it "replaces the old W-9 when they update it" do
    post my_w9_path(org.id), params: { w9: w9_params, certify: "1" }
    post my_w9_path(org.id), params: { w9: w9_params.merge(address_line1: "9 New St"), certify: "1" }

    expect(W9Submission.where(organization: org, person: person).count).to eq(2)
    expect(member.reload.current_w9.address_line1).to eq("9 New St")
  end

  it "gives them their own copy as a PDF" do
    create(:w9_submission, organization: org, person: person, organization_staff_member: member)
    get my_w9_copy_path(org.id)
    expect(response.media_type).to eq("application/pdf")
  end

  it "won't open a W-9 for an org they don't work for" do
    get my_w9_path(create(:organization, :pro).id)
    expect(response).to redirect_to(my_dashboard_path)
  end

  describe "where they're asked for it" do
    it "is a step on the onboarding page" do
      get my_onboarding_path(org.id)
      expect(response.body).to include("Share your tax info (W-9)").and include(my_w9_path(org.id, return_to: "onboarding"))
    end

    it "prompts people already on staff on My Shifts" do
      get my_shifts_path
      expect(response.body).to include("Tax info needed").and include("Fill out your W-9")
    end

    it "stops prompting once it's on file, and lists it on My Payments" do
      create(:w9_submission, organization: org, person: person, organization_staff_member: member)

      get my_shifts_path
      expect(response.body).not_to include("Tax info needed")

      get my_payments_path
      expect(response.body).to include("Tax documents").and include("W-9 on file")
    end
  end
end

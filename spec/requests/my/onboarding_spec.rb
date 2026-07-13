# frozen_string_literal: true

require "rails_helper"

RSpec.describe "My::Onboarding", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user).tap { |p| user.update!(default_person: p) } }
  let!(:org) { create(:organization, :pro) }
  let!(:member) { create(:organization_staff_member, organization: org, person: person, onboarding_state: "invited") }

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  it "shows the welcome page for the staff member's org" do
    get my_onboarding_path(org.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Welcome to the team").and include(org.name)
  end

  it "records acknowledgement but stays pending without a connected bank" do
    post my_acknowledge_onboarding_path(org.id)
    expect(response).to redirect_to(my_onboarding_path(org.id))
    member.reload
    expect(member.acknowledged?).to be(true)
    expect(member.onboarding_status).to eq(:awaiting_bank)
    expect(member).to be_pending_onboarding
  end

  it "redirects when there's no membership for this user in that org" do
    other = create(:organization, :pro)
    get my_onboarding_path(other.id)
    expect(response).to redirect_to(my_dashboard_path)
  end
end

RSpec.describe OrganizationStaffMember, "onboarding completion", type: :model do
  let(:org) { create(:organization, :pro) }
  let(:person) { create(:person) }
  let(:member) { create(:organization_staff_member, organization: org, person: person, onboarding_state: "invited") }

  it "only completes when acknowledged AND bank-connected" do
    allow(person).to receive(:can_receive_payouts?).and_return(true)

    member.refresh_onboarding_state!
    expect(member.onboarding_state).to eq("invited") # bank but never acknowledged

    member.update!(acknowledged_at: Time.current)
    member.refresh_onboarding_state!
    expect(member.onboarding_state).to eq("completed")
    expect(member.onboarding_status).to eq(:onboarded)
  end
end

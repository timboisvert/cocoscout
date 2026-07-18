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

  it "accepts a still-pending org invitation when they acknowledge (so they leave the pending list)" do
    invitation = PersonInvitation.create!(email: person.email, organization: org)
    post my_acknowledge_onboarding_path(org.id)
    expect(invitation.reload.accepted_at).to be_present
    expect(invitation).not_to be_pending
  end

  it "redirects when there's no membership for this user in that org" do
    other = create(:organization, :pro)
    get my_onboarding_path(other.id)
    expect(response).to redirect_to(my_dashboard_path)
  end
end

RSpec.describe OrganizationStaffMember, "onboarding completion", type: :model do
  let(:org) { create(:organization, :pro) }
  let(:person) { create(:person, user: create(:user)) }
  let(:member) { create(:organization_staff_member, organization: org, person: person, onboarding_state: "invited") }

  it "is complete only when acknowledged AND bank-connected (computed live, not from the cached column)" do
    # Bank connected but never acknowledged → not complete.
    person.update!(stripe_account_id: "acct_x", payouts_enabled: true)
    expect(member.onboarding_completed?).to be(false)
    expect(member.onboarding_status).to eq(:invited)

    # Acknowledged + bank → complete, even though onboarding_state was never refreshed.
    member.update!(acknowledged_at: Time.current)
    expect(member.onboarding_completed?).to be(true)
    expect(member).not_to be_pending_onboarding
    expect(member.onboarding_status).to eq(:onboarded)
  end

  it "stays pending when acknowledged but no bank yet" do
    member.update!(acknowledged_at: Time.current)
    expect(member.onboarding_completed?).to be(false)
    expect(member).to be_pending_onboarding
    expect(member.onboarding_status).to eq(:awaiting_bank)
  end
end

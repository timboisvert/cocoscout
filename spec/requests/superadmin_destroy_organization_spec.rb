# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Superadmin deletes an organization", type: :request do
  let(:password) { "Password123!" }
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let(:organization) { create(:organization) }
  let(:production) { create(:production, organization: organization) }

  before do
    post handle_signin_path, params: { email_address: superadmin.email_address, password: password }
  end

  it "deletes the organization with its productions, dates, locations, and casting" do
    location = create(:location, organization: organization)
    show = create(:show, production: production, location: location)
    audition_cycle = create(:audition_cycle, production: production)
    talent_pool = create(:talent_pool, production: production)
    role = create(:role, show: show)
    CastAssignmentStage.create!(audition_cycle: audition_cycle, talent_pool: talent_pool, assignable: role)

    delete destroy_organization_path(organization)

    expect(response).to redirect_to(organizations_list_path)
    expect(Organization.exists?(organization.id)).to be false
    expect(Production.exists?(production.id)).to be false
    expect(CastAssignmentStage.where(audition_cycle_id: audition_cycle.id)).to be_empty
  end

  it "deletes its notifications, audition votes, and a zero cash balance's ledger lines" do
    audition_cycle = create(:audition_cycle, production: production)
    session = create(:audition_session, audition_cycle: audition_cycle,
                                        location: create(:location, organization: organization))
    audition = create(:audition, audition_session: session,
                                 audition_request: create(:audition_request, audition_cycle: audition_cycle))
    AuditionVote.create!(audition: audition, user: superadmin)
    Notification.create!(organization: organization, user: superadmin, kind: "test",
                         category: NotificationGroups.keys.first, title: "Hello")
    OrgCashEntry.post!(organization: organization, entry_type: "funding", amount_cents: 1_000)
    OrgCashEntry.post!(organization: organization, entry_type: "transfer", amount_cents: -1_000)

    delete destroy_organization_path(organization)

    expect(response).to redirect_to(organizations_list_path)
    expect(Organization.exists?(organization.id)).to be false
    expect(AuditionVote.where(audition_id: audition.id)).to be_empty
  end

  it "won't delete an organization that still has money in its balance" do
    OrgCashEntry.post!(organization: organization, entry_type: "funding", amount_cents: 1_500)

    delete destroy_organization_path(organization)

    expect(response).to redirect_to(organization_detail_path(organization))
    expect(flash[:alert]).to include("$15.00 in its balance")
    expect(Organization.exists?(organization.id)).to be true
  end
end

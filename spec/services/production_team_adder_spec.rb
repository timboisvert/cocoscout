# frozen_string_literal: true

require "rails_helper"

# ProductionTeamAdder: the one way onto a production's team, from the
# Production Team tab and the contract wizard's Team step.
RSpec.describe ProductionTeamAdder do
  include ActiveJob::TestHelper

  let(:owner) { create(:user) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let(:production) { create(:production, organization: org, name: "Stargazers", production_type: "third_party") }

  it "adds someone with an account: the member role, the permission, notifications on" do
    user = create(:user)
    create(:person, user: user, name: "Clay Smith").tap { |p| user.update!(default_person: p) }

    result = described_class.add!(production, role: "manager", by: owner, user: user)
    expect(result.outcome).to eq(:added)
    expect(result.name).to eq("Clay Smith")
    expect(OrganizationRole.find_by(user: user, organization: org).company_role).to eq("member")
    expect(ProductionPermission.find_by(user: user, production: production).role).to eq("manager")
    expect(ProductionNotificationSetting.find_by(user: user, production: production).enabled).to be(true)

    expect(described_class.add!(production, role: "viewer", user: user).outcome).to eq(:already)
    expect(ProductionPermission.find_by(user: user, production: production).role).to eq("manager")
  end

  it "finds an account by email, and keeps an organization manager's role as it is" do
    user = create(:user, email_address: "priya@example.com")
    expect(described_class.add!(production, role: "viewer", email: "Priya@Example.com ").outcome).to eq(:added)
    expect(ProductionPermission.find_by(user: user, production: production).role).to eq("viewer")

    manager = create(:user)
    create(:organization_role, :manager, user: manager, organization: org)
    expect(described_class.add!(production, role: "viewer", user: manager).outcome).to eq(:already)
    expect(ProductionPermission.where(user: manager)).to be_empty
  end

  it "invites someone without an account by email, once" do
    result = nil
    expect { result = described_class.add!(production, role: "manager", email: "sam@brightlights.org", name: "Sam") }
      .to have_enqueued_mail(Manage::TeamMailer, :production_invite)
    expect(result.outcome).to eq(:invited)
    invitation = result.invitation
    expect([ invitation.email, invitation.production, invitation.invitation_role ]).to eq([ "sam@brightlights.org", production, "manager" ])

    expect(described_class.add!(production, role: "manager", email: "sam@brightlights.org").outcome).to eq(:invited_already)
    expect(TeamInvitation.where(email: "sam@brightlights.org").count).to eq(1)
  end

  it "refuses a role that isn't manager or viewer, and an invitation with no address" do
    expect { described_class.add!(production, role: "owner", email: "x@example.com") }.to raise_error(ArgumentError)
    expect { described_class.add!(production, role: "manager", email: "not an email") }.to raise_error(ArgumentError)
  end
end

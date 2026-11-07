# frozen_string_literal: true

require "rails_helper"

# Team invitations are sent from a job, so the mailer only has the record: who
# invited must be stored on it. For nine months the mailer named an inviter
# the record never had (and the organization invite built its link with a
# route helper that doesn't exist), so no invitation email ever went out.
RSpec.describe Manage::TeamMailer, type: :mailer do
  let(:owner) { create(:user) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let(:production) { create(:production, organization: org, name: "Stargazers") }
  let(:inviter) { create(:person, user: owner, name: "Clay Smith") }

  before do
    ContentTemplate.find_by!(key: "team_organization_invitation").update!(body: "<p>{{inviter_name}} invites you to {{organization_name}}: {{accept_url}}</p>")
    ContentTemplate.find_by!(key: "team_production_invitation").update!(body: "<p>{{inviter_name}} invites you to {{production_name}}: {{accept_url}}</p>")
  end

  it "names who sent an organization invitation, with a link that accepts it" do
    invitation = create(:team_invitation, organization: org, email: "sam@brightlights.org", invited_by: inviter)

    mail = described_class.invite(invitation).deliver_now

    expect(mail.to).to eq([ "sam@brightlights.org" ])
    expect(mail.html_part.decoded).to include("Clay Smith invites you to Stars & Garters")
    expect(mail.html_part.decoded).to include("/manage/team_invitations/accept/#{invitation.token}")
  end

  it "names who sent a production invitation" do
    invitation = create(:team_invitation, organization: org, production: production, email: "sam@brightlights.org", invited_by: inviter)

    mail = described_class.production_invite(invitation).deliver_now

    expect(mail.html_part.decoded).to include("Clay Smith invites you to Stargazers")
    expect(mail.html_part.decoded).to include("/manage/team_invitations/accept/#{invitation.token}")
  end

  # Invitations sent before the inviter was recorded, and ones sent by a user
  # with no profile.
  it "says a team member sent it when no one is recorded" do
    invitation = create(:team_invitation, organization: org, production: production)

    expect(described_class.production_invite(invitation).deliver_now.html_part.decoded).to include("A team member invites you")
    expect(described_class.invite(invitation).deliver_now.html_part.decoded).to include("A team member invites you")
  end
end

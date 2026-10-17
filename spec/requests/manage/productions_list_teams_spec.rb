# frozen_string_literal: true

require "rails_helper"

# The Productions list is rows (Tim, 2026-10-17): poster and name on the
# left, the production team's headshots on the right with names on hover,
# so a manager sees which productions have no production team.
RSpec.describe "Productions list with production teams", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, email_address: "owner@sg.example", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:staffed) { create(:production, organization: org, name: "Boylesque", production_type: "in_house") }
  let!(:bare) { create(:production, organization: org, name: "Hags", production_type: "third_party") }
  let(:clay) { create(:user, email_address: "clay@sg.example", password: password) }
  let!(:clay_person) { create(:person, user: clay, name: "Clay Smith") }

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    create(:organization_role, user: clay, organization: org, company_role: "member")
    clay.update!(default_person: clay_person)
    ProductionPermission.create!(user: clay, production: staffed, role: "manager")
    TeamInvitation.create!(organization: org, production: staffed, email: "dan@example.test", invitation_role: "viewer")
    create(:show, production: staffed, date_and_time: 9.days.from_now.change(hour: 19))
  end

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
    post set_organization_path(id: org.id)
  end

  it "shows a manager each production's team, who's still invited, and which has none" do
    sign_in(owner)
    get manage_productions_path
    html = response.body.gsub(/\s+/, " ")
    expect(html).to include("Clay Smith · production team manager", "dan@example.test · invited as a production team viewer, not yet accepted",
                            "No production team assigned", "#{edit_manage_production_path(bare)}#tab-3",
                            "First-party · Next date #{9.days.from_now.strftime('%b %-d')}", "Contract · No upcoming dates")
    expect(html.scan("No production team assigned").size).to eq(1)
  end

  it "shows a production team manager their productions with themselves marked, and no type words" do
    sign_in(clay)
    get manage_productions_path
    html = response.body.gsub(/\s+/, " ")
    expect(html).to include("You · production team manager", "ring-pink-400", "Boylesque")
    expect(html).not_to include("Hags", "First-party", "No production team assigned")
  end
end

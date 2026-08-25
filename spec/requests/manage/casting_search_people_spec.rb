# frozen_string_literal: true

require "rails_helper"

# The Add Person modal's search built headshot URLs with the bare route
# helpers (no host configured), so the URL generation always raised, was
# rescued to nil, and every search result fell back to initials. The
# controller's own url_for knows the request host and actually works.
RSpec.describe "Manage::Casting search_people headshots", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org) }
  let(:show) { create(:show, production: production) }

  before do
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "returns a usable headshot_url for a person with a headshot" do
    person = create(:person, name: "Framed Fanny")
    org.people << person
    create(:profile_headshot, :primary, :with_image, profileable: person)

    get manage_casting_search_people_path(production, q: "Framed", show_id: show.id)

    payload = JSON.parse(response.body)["people"].find { |p| p["name"] == "Framed Fanny" }
    expect(payload["headshot_url"]).to be_present
    expect(payload["headshot_url"]).to include("http")
  end

  it "returns a nil headshot_url for a person without one" do
    person = create(:person, name: "Blank Betty")
    org.people << person

    get manage_casting_search_people_path(production, q: "Blank", show_id: show.id)

    payload = JSON.parse(response.body)["people"].find { |p| p["name"] == "Blank Betty" }
    expect(payload).to be_present
    expect(payload["headshot_url"]).to be_nil
  end

  it "returns a usable headshot_url for a group with a headshot" do
    group = create(:group, name: "Framed Fivesome")
    org.groups << group
    create(:profile_headshot, :primary, :with_image, profileable: group)

    get manage_casting_search_people_path(production, q: "Framed", show_id: show.id, include_groups: "true")

    payload = JSON.parse(response.body)["groups"].find { |g| g["name"] == "Framed Fivesome" }
    expect(payload["headshot_url"]).to be_present
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::People orphaned pool members", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:pool) { TalentPool.create!(production: production, name: "Pool") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "removing from the org also removes talent-pool memberships (no orphan left behind)" do
    person = create(:person)
    org.people << person
    pool.people << person

    post remove_from_organization_manage_person_path(person)

    expect(org.people.exists?(person.id)).to be(false)
    expect(pool.people.exists?(person.id)).to be(false) # the fix: pool membership gone too
  end

  it "loads the profile of a person who's in the org's pool but not in org.people" do
    orphan = create(:person)
    pool.people << orphan # in the pool, never in org.people
    expect(org.people.exists?(orphan.id)).to be(false)

    get manage_person_path(orphan)

    expect(response).to have_http_status(:ok) # not a 404
  end

  it "still 404s for a person with no connection to the org at all" do
    stranger = create(:person)

    get manage_person_path(stranger)

    expect(response).to have_http_status(:not_found)
  end
end

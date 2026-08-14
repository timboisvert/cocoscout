# frozen_string_literal: true

require "rails_helper"

# The wide, multi-column production filter dropdown with production-type chips
# (shared/filters/production_dropdown_filter) on the org shows list.
RSpec.describe "Production filter dropdown", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "renders type chips when the productions span types" do
    create(:production, organization: org, name: "House Show")
    create(:production, organization: org, name: "Renter Gig", production_type: "third_party")

    get manage_shows_path

    expect(response.body).to include("All types")
    expect(response.body).to include("In-house").and include("Contracts")
    expect(response.body).to include('data-type="third_party"')
  end

  it "hides the chips when every production is the same type" do
    create(:production, organization: org, name: "House Show")
    create(:production, organization: org, name: "Second House Show")

    get manage_shows_path

    expect(response.body).not_to include("All types")
  end
end

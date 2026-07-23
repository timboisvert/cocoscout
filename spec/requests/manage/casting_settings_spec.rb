# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::CastingSettings", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "opens on the casting source section with a strip to the others" do
    get manage_casting_settings_path(production)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Choose where cast members for this production come from")
    expect(response.body).to include(manage_casting_settings_section_path(production_id: production, section: "roles"))
    expect(response.body).to include(manage_casting_settings_section_path(production_id: production, section: "talent_pool"))
  end

  it "renders the roles section" do
    production.roles.create!(name: "Host")

    get manage_casting_settings_section_path(production_id: production, section: "roles")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Host")
  end

  it "renders the talent pool section, which had no reachable home before" do
    get manage_casting_settings_section_path(production_id: production, section: "talent_pool")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("available for casting in this production")
  end

  it "sends the standalone talent pool URL to its section" do
    get manage_casting_talent_pool_path(production)

    expect(response).to redirect_to(
      manage_casting_settings_section_path(production_id: production, section: "talent_pool")
    )
  end

  it "sends an unknown section back to the default" do
    get manage_casting_settings_section_path(production_id: production, section: "nope")

    expect(response).to redirect_to(manage_casting_settings_path(production))
  end
end

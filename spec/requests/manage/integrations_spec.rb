# frozen_string_literal: true

require "rails_helper"

# Organization settings → Integrations (plan §9.3): the home, Square's
# page before and after connecting, the sign-in round trip, mapping, and
# disconnecting.
RSpec.describe "Manage::Integrations", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:lodge) { create(:location, organization: org, name: "Lincoln Lodge") }

  before do
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    allow(SquareApi).to receive(:application_id).and_return("app-id")
    allow(SquareApi).to receive(:application_secret).and_return("app-secret")
  end

  it "has an Integrations section with Square, the roadmap, tickets elsewhere and the bank" do
    get section_manage_organization_path(org, section: "integrations")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Registers and bars", "Square", "Connect with Square", "Clover", "Toast", "Eventbrite", "Ticket Tailor", "Your bank", "What happens to your file")
  end

  it "connects through Square's own sign-in and comes back connected" do
    get manage_organization_square_path(org)
    expect(response.body).to include("Connect Square", "never sees your Square password")

    post manage_connect_organization_square_path(org)
    expect(response).to have_http_status(:redirect)
    expect(response.location).to start_with("https://connect.squareup.com/oauth2/authorize?")
    state = Rack::Utils.parse_query(URI(response.location).query)["state"]
    expect(state).to be_present

    expect(SquareApi).to receive(:exchange_code).with("the-code", redirect_uri: manage_square_callback_url)
      .and_return({ "access_token" => "tok", "refresh_token" => "ref", "expires_at" => 30.days.from_now.iso8601, "merchant_id" => "M1" })
    api = instance_double(SquareApi, locations: [ { "id" => "L1", "name" => "The bar", "address" => { "address_line_1" => "4008 N Lincoln" } } ],
                                     catalog: [ { "type" => "CATEGORY", "id" => "C1", "category_data" => { "name" => "Beer" } } ],
                                     merchant: { "business_name" => "Stars and Garters LLC" })
    allow(SquareApi).to receive(:new).and_return(api)

    expect {
      get manage_square_callback_path(code: "the-code", state: state)
    }.to have_enqueued_job(SquarePullJob)
    expect(response).to redirect_to(manage_organization_square_path(org))
    integration = org.integrations.square.first
    expect(integration).to be_connected
    expect(integration.access_token).to eq("tok")
    expect(integration.merchant_id).to eq("M1")
    expect(integration.connected_by).to eq(owner)
    expect(integration.external_locations.first["name"]).to eq("The bar")

    get manage_organization_square_path(org)
    expect(response.body).to include("Connected", "Stars and Garters LLC", "The bar", "Beer", "Pull now", "Not ours, skip it")

    patch manage_organization_square_path(org), params: { location_map: { "L1" => lodge.id.to_s }, category_map: { "C1" => "bar" }, brings: { "sales" => "1", "tips" => "1", "tax" => "1", "refunds" => "1", "fees" => "1" } }
    integration.reload
    expect(integration.our_location_id("L1")).to eq(lodge.id)
    expect(integration.our_category("C1")).to eq("bar")
    expect(integration.brings?("deposits")).to be(false)
    expect(integration.brings?("sales")).to be(true)

    allow(SquareApi).to receive(:revoke)
    delete manage_organization_square_path(org)
    expect(integration.reload).not_to be_connected
    expect(integration.access_token).to be_nil
  end

  it "refuses a callback whose state does not match" do
    get manage_square_callback_path(code: "x", state: "nope")
    expect(response).to redirect_to(manage_organizations_path)
    expect(org.integrations.count).to eq(0)
  end
end

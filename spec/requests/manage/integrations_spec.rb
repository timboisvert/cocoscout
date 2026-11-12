# frozen_string_literal: true

require "rails_helper"

# Organization settings → Integrations → Square (plan §9.3): the connect
# round trip with its state check, the mappings, Pull now, disconnect.
RSpec.describe "Manage::Integrations Square", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:bar) { create(:location, organization: org, name: "The bar") }

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  before do
    allow(SquareApi).to receive_messages(application_id: "sandbox-sq0idb-app", application_secret: "sandbox-sq0csb-secret")
    sign_in(owner)
  end

  describe "connecting" do
    it "sends the owner to Square with a state, and the callback with that state connects the organization" do
      post manage_connect_organization_square_path(org)
      expect(response).to redirect_to(%r{\Ahttps://connect\.squareup(sandbox)?\.com/oauth2/authorize\?})
      state = Rack::Utils.parse_query(URI(response.location).query)["state"]
      expect(state).to be_present

      allow(SquareApi).to receive(:exchange_code).with("the-code", redirect_uri: manage_square_callback_url)
        .and_return({ "access_token" => "tok", "refresh_token" => "ref", "expires_at" => 30.days.from_now.iso8601, "merchant_id" => "M1" })
      allow(SquareSync).to receive(:refresh_catalog!)

      expect {
        get manage_square_callback_path, params: { code: "the-code", state: state }
      }.to have_enqueued_job(SquarePullJob).with(anything, hash_including(trigger: "manual"))

      expect(response).to redirect_to(manage_organization_square_path(org))
      integration = org.integrations.square.first
      expect(integration).to be_connected
      expect(integration.access_token).to eq("tok")
      expect(integration.merchant_id).to eq("M1")
      expect(integration.connected_by).to eq(owner)
      expect(SquareSync).to have_received(:refresh_catalog!).with(integration)
    end

    it "refuses a callback whose state is not the one it sent" do
      post manage_connect_organization_square_path(org)
      allow(SquareApi).to receive(:exchange_code)

      get manage_square_callback_path, params: { code: "the-code", state: "someone-elses" }

      expect(response).to redirect_to(manage_organizations_path)
      expect(flash[:alert]).to include("did not match")
      expect(org.integrations).to be_empty
      expect(SquareApi).not_to have_received(:exchange_code)
    end

    it "says why when Square sends back an error instead of a code" do
      post manage_connect_organization_square_path(org)
      state = Rack::Utils.parse_query(URI(response.location).query)["state"]

      get manage_square_callback_path, params: { state: state, error: "access_denied", error_description: "The seller said no" }

      expect(response).to redirect_to(section_manage_organization_path(org, section: "integrations"))
      expect(flash[:alert]).to include("The seller said no")
      expect(org.integrations).to be_empty
    end

    it "says why when the code cannot be exchanged" do
      post manage_connect_organization_square_path(org)
      state = Rack::Utils.parse_query(URI(response.location).query)["state"]
      allow(SquareApi).to receive(:exchange_code).and_raise(SquareApi::Error, "Not Authorized")

      get manage_square_callback_path, params: { code: "the-code", state: state }

      expect(flash[:alert]).to eq("Square did not connect: Not Authorized")
      expect(org.integrations).to be_empty
    end

    it "stops before Square when the server's secret is an access token pasted from the wrong page" do
      allow(SquareApi).to receive(:application_secret).and_return("EAAAl-not-a-secret")

      get manage_organization_square_path(org)
      expect(response.body).to include("is an access token, not the Application Secret")
      expect(response.body).not_to include("Connect with Square")

      post manage_connect_organization_square_path(org)
      expect(response).to redirect_to(manage_organization_square_path(org))
      expect(flash[:alert]).to include("Application Secret is on the app")
    end

    it "says Square is not set up when the server has no keys" do
      allow(SquareApi).to receive(:application_id).and_return(nil)

      get manage_organization_square_path(org)
      expect(response.body).to include("Square is not set up on this server yet.")
    end
  end

  describe "once connected" do
    let!(:integration) do
      org.integrations.create!(provider: "square", status: "connected", tokens: { "access_token" => "tok", "merchant_id" => "M1" },
                               settings: { "locations" => [ { "id" => "L1", "name" => "Default Test Account" } ],
                                           "categories" => [ { "id" => "C1", "name" => "Drinks" } ] })
    end

    it "shows the page with the location and category to map" do
      get manage_organization_square_path(org)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Default Test Account").and include("Drinks").and include("Pull now")
    end

    it "saves the mappings and re-links the days already read" do
      day = integration.register_days.create!(organization: org, external_location_id: "L1", business_date: Date.current, orders_count: 2, gross_cents: 1_000)

      patch manage_organization_square_path(org), params: { location_map: { "L1" => bar.id.to_s }, category_map: { "C1" => "bar" }, brings: { "tips" => "1" } }

      expect(response).to redirect_to(manage_organization_square_path(org))
      integration.reload
      expect(integration.our_location_id("L1")).to eq(bar.id)
      expect(integration.our_category("C1")).to eq("bar")
      expect(integration.brings?("tips")).to be(true)
      expect(integration.brings?("fees")).to be(false)
      expect(day.reload.location).to eq(bar)
    end

    it "queues a pull of the last week" do
      expect { post manage_pull_organization_square_path(org) }.to have_enqueued_job(SquarePullJob).with(integration.id, hash_including(trigger: "manual"))
      expect(response).to redirect_to(manage_organization_square_path(org))
    end

    it "disconnects, revoking the token at Square" do
      allow(SquareApi).to receive(:revoke).with("tok").and_return({})

      delete manage_organization_square_path(org)

      expect(response).to redirect_to(section_manage_organization_path(org, section: "integrations"))
      expect(integration.reload.status).to eq("disconnected")
      expect(integration.access_token).to be_nil
      expect(SquareApi).to have_received(:revoke)
    end
  end

  it "is for the organization's managers only" do
    stranger = create(:user, password: password)
    sign_in(stranger)

    get manage_organization_square_path(org)
    expect(response).not_to have_http_status(:ok)
  end
end

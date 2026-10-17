# frozen_string_literal: true

require "rails_helper"

# The Data page lists every index. An expression index — house_services'
# unique (organization_id, lower(name)) — comes back from the connection with
# its columns as one string, and joining it took the page down (2026-10-16).
RSpec.describe "Superadmin data monitor", type: :request do
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: "Password123!") }

  before { post handle_signin_path, params: { email_address: superadmin.email_address, password: "Password123!" } }

  it "lists an expression index like any other" do
    get data_monitor_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("index_house_services_on_org_and_name", "organization_id, lower((name)::text)")
  end
end

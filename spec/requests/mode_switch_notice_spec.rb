# frozen_string_literal: true

require "rails_helper"

# The soft pink notice after every switch (Tim, 2026-10-21): entering
# production mode (straight in, or through the organization picker), switching
# organization from the picker or an opener, and leaving production mode.
# Shown once, on the first page after the switch.
RSpec.describe "The mode switch notice", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:starlight) { create(:organization, name: "Starlight Theater", owner: user) }
  let!(:starlight_role) { create(:organization_role, :manager, user: user, organization: starlight) }

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  def notice(body)
    Nokogiri::HTML(body).at_css("[data-mode-switch-notice]")&.text&.squish
  end

  it "says you're in production mode when a link brings you straight in, and that you left when you go back" do
    get my_dashboard_path
    get manage_path
    expect(notice(response.body)).to include("You're in production mode for Starlight Theater")
    get manage_shows_path
    expect(notice(response.body)).to be_nil

    get my_dashboard_path
    expect(notice(response.body)).to eq("You left production mode for Starlight Theater.")
    get my_tasks_path
    expect(notice(response.body)).to be_nil
  end

  # Tim, 2026-10-28: the notice came up on every page in production mode. A
  # browser cookie stuck on "my" (another web view, another tab) can't bring it
  # back once the account knows this person is working in production mode.
  it "stays away on every later page even when this browser's cookie is stuck on My" do
    get my_dashboard_path
    get manage_path
    expect(notice(response.body)).to include("You're in production mode")
    expect(user.reload.last_mode).to eq("manage")

    allow_any_instance_of(Manage::ManageController).to receive(:last_mode).and_return("my") # rubocop:disable RSpec/AnyInstance -- the stale cookie, from outside
    [ manage_shows_path, manage_casting_path, manage_path ].each do |path|
      get path
      expect(notice(response.body)).to be_nil, "notice on #{path}"
    end
  end

  it "never says it on a prefetch" do
    get my_dashboard_path
    get manage_path, headers: { "X-Sec-Purpose" => "prefetch" }
    expect(notice(response.body)).to be_nil
  end

  it "says Switched to … after the organization picker, entering or changing organization" do
    moonlight = create(:organization, name: "Moonlight Players", owner: user)
    create(:organization_role, :manager, user: user, organization: moonlight)

    get my_dashboard_path
    get select_organization_path
    expect(response).to have_http_status(:ok)
    post set_organization_path(id: moonlight.id)
    follow_redirect!
    expect(notice(response.body)).to include("Switched to Moonlight Players")
    get manage_shows_path
    expect(notice(response.body)).to be_nil

    post set_organization_path(id: starlight.id)
    follow_redirect!
    expect(notice(response.body)).to include("Switched to Starlight Theater")

    # The same organization again: nothing to say.
    post set_organization_path(id: starlight.id)
    follow_redirect!
    expect(notice(response.body)).to be_nil
  end
end

# frozen_string_literal: true

require "rails_helper"

# The session, which holds the organization someone is working in, ends when
# the browser quits or the app is closed, though they stay signed in. Someone
# with several organizations was asked to pick one again every time they came
# back (Tim, 2026-11-09). The browser, or the phone's app, now keeps the last
# one, and comes back to it.
RSpec.describe "Coming back to the organization you were in", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:starlight) { create(:organization, :pro, name: "Starlight Theater", owner: user) }
  let!(:moonlight) { create(:organization, name: "Moonlight Players", owner: user) }
  let(:session_key) { Rails.application.config.session_options[:key] }

  before do
    create(:organization_role, :manager, user: user, organization: starlight)
    create(:organization_role, :manager, user: user, organization: moonlight)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  # The browser quit: the session cookie is gone, the sign-in is not.
  def quit_the_browser
    expect(cookies[session_key]).to be_present
    cookies.delete(session_key)
  end

  it "asks someone with several organizations to pick one the first time" do
    get manage_path
    expect(response).to redirect_to(select_organization_path)
  end

  it "comes back to the one they were in, on the website and in the app" do
    post set_organization_path(id: moonlight.id)
    get manage_path
    expect(response).to have_http_status(:ok)

    quit_the_browser
    get manage_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Moonlight Players")

    quit_the_browser
    get manage_path, headers: { "User-Agent" => "CocoScout/1.1.4 (9; nav 2) CocoMenu/bar Hotwire Native iOS; Turbo Native iOS; bridge-components: [form menu push]" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Moonlight Players")
  end

  it "follows a switch: the last one chosen is the one kept" do
    post set_organization_path(id: moonlight.id)
    get manage_path
    post set_organization_path(id: starlight.id)
    get manage_path

    quit_the_browser
    get manage_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Starlight Theater")
  end

  it "asks again when they no longer belong to the one it kept" do
    post set_organization_path(id: moonlight.id)
    get manage_path
    third = create(:organization, name: "Third Stage", owner: user)
    create(:organization_role, :manager, user: user, organization: third)
    OrganizationRole.where(user: user, organization: moonlight).destroy_all
    moonlight.update!(owner: create(:user))

    quit_the_browser
    get manage_path
    expect(response).to redirect_to(select_organization_path)
  end

  it "keeps one person's organization from another's on a shared browser" do
    post set_organization_path(id: moonlight.id)
    get manage_path

    other = create(:user, password: password)
    theirs = create(:organization, name: "Their Company", owner: other)
    create(:organization_role, :manager, user: other, organization: theirs)
    also = create(:organization, name: "Their Second", owner: other)
    create(:organization_role, :manager, user: other, organization: also)
    get signout_path
    post handle_signin_path, params: { email_address: other.email_address, password: password }
    get manage_path
    expect(response).to redirect_to(select_organization_path)
  end
end

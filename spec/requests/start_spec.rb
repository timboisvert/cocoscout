# frozen_string_literal: true

require "rails_helper"

RSpec.describe "The V1.1 app's /start", type: :request do
  let(:app_ua) { "CocoScout/1.1 (12; nav 2) Mozilla/5.0 (iPhone) Hotwire Native iOS; Turbo Native iOS" }

  it "sends someone signed out to the app's welcome screen" do
    get start_path, headers: { "User-Agent" => app_ua }
    expect(response).to redirect_to(welcome_path)
  end

  it "opens My for someone who last used it" do
    user = create(:user)
    post handle_signin_path, params: { email_address: user.email_address, password: user.password }
    get start_path, headers: { "User-Agent" => app_ua }
    expect(response).to redirect_to(my_dashboard_path)
  end

  it "opens production mode for someone who last used it" do
    user = create(:user)
    person = Person.create!(email: user.email_address, name: "Someone", user: user)
    org = Organization.create!(name: "Start Org", owner: user)
    OrganizationRole.create!(user: user, organization: org, company_role: "manager")
    org.people << person
    post handle_signin_path, params: { email_address: user.email_address, password: user.password }
    get manage_path
    get start_path, headers: { "User-Agent" => app_ua }
    expect(response).to redirect_to(manage_path)
  end
end

# frozen_string_literal: true

require "rails_helper"

# Where the app still floats the Coco button over the page's bottom-right
# corner (installs before 1.1.4), every app page ends well above the bottom
# (Tim, 2026-11-02). The website, and app builds with Coco in their top bar
# (Tim, 2026-11-09), keep the usual padding.
RSpec.describe "Room for the Coco button at the foot of app pages", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user, name: "Page Foot") }
  let(:app_ua) { "CocoScout/1.1 (12; nav 2) Turbo Native iOS" }
  let(:bar_ua) { "CocoScout/1.1.4 (9; nav 2) CocoMenu/bar Turbo Native iOS; bridge-components: [form menu push]" }

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  def main_class(path, headers = {})
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body).at_css("main")["class"]
  end

  it "ends an app page 112px above the bottom and a web page 32px" do
    expect(main_class(my_shifts_path, "User-Agent" => app_ua)).to include("pb-28")
    expect(main_class(my_shifts_path)).to include("pb-8")
  end

  it "does the same on the profile layout" do
    expect(main_class(profile_path, "User-Agent" => app_ua)).to include("pb-28")
    expect(main_class(profile_path)).not_to include("pb-28")
  end

  it "leaves no room at the foot for a build with Coco in its top bar, and sends it nothing to move a button with" do
    expect(main_class(my_shifts_path, "User-Agent" => bar_ua)).to include("pb-8")
    expect(response.body).not_to include("bridge--menu-button")
    expect(main_class(profile_path, "User-Agent" => bar_ua)).not_to include("pb-28")

    get my_shifts_path, headers: { "User-Agent" => "#{app_ua}; bridge-components: [form menu menu-button push]" }
    expect(response.body).to include("bridge--menu-button")
  end
end

# frozen_string_literal: true

require "rails_helper"

# In the app the floating Coco button is drawn over the page's bottom-right
# corner, so every app page ends well above the bottom; the website keeps its
# usual padding (Tim, 2026-11-02).
RSpec.describe "Room for the Coco button at the foot of app pages", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user, name: "Page Foot") }
  let(:app_ua) { "CocoScout/1.1 (12; nav 2) Turbo Native iOS" }

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
end

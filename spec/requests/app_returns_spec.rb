# frozen_string_literal: true

require "rails_helper"

# The way back into the iOS app from its secure sheet: a cocoscout:// link
# naming a page in My, and never anywhere else.
RSpec.describe "Returning to the app", type: :request do
  it "hands the app the page in My to open, without needing a sign-in" do
    get app_return_path(to: "/my/payments/connect/return")
    expect(response).to redirect_to("cocoscout://open?path=%2Fmy%2Fpayments%2Fconnect%2Freturn")
  end

  it "sends anything outside My to My itself" do
    [ "https://evil.example/my", "//evil.example", "/manage/money", "/my/../manage", "" ].each do |to|
      get app_return_path(to: to)
      expect(response).to redirect_to("cocoscout://open?path=%2Fmy"), "for #{to.inspect}"
    end
  end
end

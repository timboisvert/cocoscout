# frozen_string_literal: true

require "rails_helper"

# V1.1 plan Phase 2: compose on a phone is a full-screen sheet with its
# buttons pinned to the bottom, clear of the Coco button in the app.
RSpec.describe "Compose on a phone", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:app_ua) { "CocoScout/1.1 (12; nav 2) Turbo Native iOS" }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def compose(headers = {})
    get manage_path
    get messages_path, headers: headers
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body).at_css("#compose-message-modal")
  end

  it "fills the screen on a phone and pins both steps' buttons to the bottom" do
    modal = compose
    sheet = modal.at_css("[data-compose-phone-sheet]")
    expect(sheet["class"]).to include("max-sm:min-h-[100dvh]", "max-sm:rounded-none")
    bars = modal.css("[data-compose-phone-actions]")
    expect(bars.size).to eq(2)
    bars.each { |bar| expect(bar["class"]).to include("max-sm:sticky", "max-sm:bottom-0") }
    expect(bars.last.text).to include("Send Message")
  end

  it "stacks the who-to-message choices on a phone" do
    expect(compose.at_css("[data-compose-message-target='recipientCards']")["class"]).to include("grid-cols-1", "sm:grid-cols-3")
  end

  it "keeps the buttons clear of the Coco button in the app" do
    compose("User-Agent" => app_ua).css("[data-compose-phone-actions]").each do |bar|
      expect(bar["class"]).to include("max-sm:pr-[96px]")
    end
    compose.css("[data-compose-phone-actions]").each do |bar|
      expect(bar["class"]).not_to include("pr-[96px]")
    end
  end
end

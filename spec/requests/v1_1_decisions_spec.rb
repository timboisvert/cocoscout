# frozen_string_literal: true

require "rails_helper"

# Decisions in the V1.1 plan's §0a and the leftovers of its §6, checked end
# to end (2026-10-21).
RSpec.describe "V1.1 decisions", type: :request do
  let(:password) { "Password123!" }
  let(:app_ua) { "CocoScout/1.1 (12; nav 2) Mozilla/5.0 (iPhone) Hotwire Native iOS; Turbo Native iOS" }

  it "never pitches producing in the apps: Start producing is website-only" do
    performer = create(:user, password: password)
    create(:person, user: performer).tap { |p| performer.update!(default_person: p) }
    post handle_signin_path, params: { email_address: performer.email_address, password: password }
    get my_dashboard_path
    expect(response.body).to include("Start producing")
    get my_dashboard_path, headers: { "User-Agent" => app_ua }
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Start producing")
  end

  it "keeps superadmin, billing and the marketing pages out of the app" do
    rules = JSON.parse(Rails.root.join("public/hotwire-native/nav-2/path-configuration.json").read)["rules"]
    safari = rules.find { |r| r.dig("properties", "open_in") == "safari" }
    expect(safari["patterns"]).to include("^/superadmin", "^/manage/billing", "^/pricing", "^/for-producers")
  end

  it "reorders roles by touch from the grip only, so the page still scrolls over the cards" do
    owner = create(:user, password: password)
    org = create(:organization, :pro, owner: owner)
    create(:organization_role, :manager, user: owner, organization: org)
    production = create(:production, organization: org)
    create(:role, production: production, name: "Lead")
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_casting_settings_section_path(production, section: "roles")
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    card = doc.at_css("[data-role-order-target='item']")
    expect(card["data-action"]).not_to include("touchstart")
    grip = card.at_css("[data-role-order-grip]")
    expect(grip["data-action"]).to include("touchstart->role-order#touchStart", "touchmove->role-order#touchMove")
    expect(grip["class"]).to include("touch-none")
    js = Rails.root.join("app/javascript/controllers/role_order_controller.js").read
    expect(js).to include("if (this.touchMoved) this.saveOrder()")
  end
end

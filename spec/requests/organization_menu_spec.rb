# frozen_string_literal: true

require "rails_helper"

# The organization menu (shared/navigation/organization_menu_items; Tim's
# review, 2026-10-21): where you are, Exit production mode, the other
# organizations to switch to, this organization's pages, New organization.
# The account menu keeps Enter only; the Productions item has no count.
RSpec.describe "The organization menu", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:starlight) { create(:organization, :pro, name: "Starlight Theater", owner: user) }
  let!(:starlight_role) { create(:organization_role, :manager, user: user, organization: starlight) }
  let!(:moonlight) { create(:organization, name: "Moonlight Players", owner: user) }
  let!(:moonlight_role) { create(:organization_role, :manager, user: user, organization: moonlight) }

  before do
    post handle_signin_path, params: { email_address: user.email_address, password: password }
    post set_organization_path(id: starlight.id)
  end

  it "says where you are, offers the way out, the other organization, and this organization's pages, in that order" do
    get manage_path
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    menu = doc.at_css("[data-organization-menu-current]").parent
    text = menu.text.squish
    expect(text).to include("Starlight Theater Owner · Pro")
    expect(text.index("Exit production mode")).to be < text.index("Switch to")
    expect(text.index("Switch to")).to be < text.index("Moonlight Players")
    expect(text.index("Moonlight Players")).to be < text.index("This organization")
    expect(text).to include("Organization settings", "Plan and billing", "Productions", "New organization")
    expect(text).not_to include("Starlight Theater Owner · Pro Switch to Starlight") # not itself under Switch to
    # The pink bar is the same component as My's Enter bar.
    expect(menu.at_css("a[href='#{my_dashboard_path}']")["class"]).to include("bg-pink-500")
  end

  it "keeps Exit out of the account menu in production mode, and Enter in it on My" do
    get manage_path
    account = Nokogiri::HTML(response.body).css("[role='menu']").find { |m| m.text.include?("Signed in as") }
    expect(account.text).not_to include("Exit production mode", "Start producing")

    get my_dashboard_path
    account = Nokogiri::HTML(response.body).css("[role='menu']").find { |m| m.text.include?("Signed in as") }
    expect(account.text).to include("Enter production mode")
  end

  it "shows Productions in the nav without a count" do
    create(:production, organization: starlight)
    create(:production, organization: starlight)
    get manage_path
    doc = Nokogiri::HTML(response.body)
    link = doc.css("a[href='#{manage_productions_path}']").find { |a| a.text.squish == "Productions" && a.parent["class"].to_s.include?("relative") }
    expect(link).to be_present
    expect(link.parent.text.squish).to eq("Productions")
  end
end

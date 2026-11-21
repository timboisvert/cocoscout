# frozen_string_literal: true

require "rails_helper"

# Tim, 2026-11-20: a settings page's sections are a list down its left side
# (shared/section_list), in place of a tab strip that ran off the page once
# there were more tabs than fit. The phone keeps its row and sheet
# (shared/section_picker), under the same headings.
RSpec.describe "A settings page's sections down the side", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Variety Hour") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def doc
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body)
  end

  def headings(node)
    node.css("h3").map { |h| h.text.squish }
  end

  it "lists a settings page's sections as links, with the one showing marked" do
    get manage_money_settings_path
    list = doc.at_css("nav[data-section-list]")
    expect(list["class"]).to include("hidden md:block")
    links = list.css("a")
    expect(links.size).to be > 1
    expect(links.count { |a| a["aria-current"] == "page" }).to eq(1)
    expect(headings(list)).to be_empty
    expect(doc.at_css("[data-settings-sections] [data-section-picker]")["class"]).to include("md:hidden")
    expect(response.body).not_to include("overflow-x-auto overflow-y-hidden")
  end

  it "puts a long settings page's sections under headings, in the list and in the phone's sheet" do
    get manage_ticketing_settings_path
    list = doc.at_css("nav[data-section-list]")
    expect(headings(list)).to eq([ "Box office", "Money", "Emails and sharing" ])
    expect(list.css("a").map { |a| a.text.squish }).to eq(
      [ "Basic info", "Door", "Pages", "Fees and taxes", "Comps", "Refunds", "Notifications and emails", "Sales visibility" ]
    )
    sheet = doc.at_css("#settings-sections-sheet")
    expect(sheet.css("a").map { |a| a.text.squish }).to eq(list.css("a").map { |a| a.text.squish })
    expect(sheet.text).to include("Box office", "Money", "Emails and sharing")
  end

  it "lists a production's sections as the tabs controller's tabs, the Danger Zone set apart at the foot" do
    get edit_manage_production_path(production)
    tabs = doc.at_css("[data-controller='tabs']")
    list = tabs.at_css("nav[data-section-list]")
    expect(headings(list)).to eq(%w[Details People Business Public])
    lines = list.css("button[data-tabs-target='tab']")
    expect(lines.map { |b| b["data-index"].to_i }).to eq((0...lines.size).to_a)
    expect(lines.map { |b| b["data-action"] }.uniq).to eq([ "tabs#select" ])
    expect(lines.map { |b| b.key?("data-section-list-item") }).to all(be(true))
    expect(lines.first["aria-current"]).to eq("true")
    expect(lines.last.text.squish).to eq("Danger Zone")
    expect(lines.last["data-idle-class"]).to include("text-red-500")
    expect(tabs.css("[data-tabs-target='panel']").size).to eq(lines.size)
  end

  it "gives a show's settings the same list, with Linked Events under Details" do
    show = create(:show, production: production)
    get manage_edit_show_path(production, show)
    list = doc.at_css("nav[data-section-list]")
    expect(headings(list).first).to eq("Details")
    names = list.css("button").map { |b| b.text.squish.delete_suffix(" Pro") }
    expect(names.first(4)).to eq([ "Basic Information", "Schedule", "Location", "Linked Events" ])
    expect(names.last).to eq("Danger Zone")
    linked = list.css("button").find { |b| b.text.squish == "Linked Events" }
    expect(linked["data-index"].to_i).to eq(names.size - 2)
  end

  # In the app the Section row opens the phone's own menu
  # (bridge/sections_controller.js), on builds that register "sections".
  it "tells the app's menu where the row is and what the sections are" do
    get edit_manage_production_path(production)
    picker = doc.at_css("[data-production-edit-sections] [data-section-picker]")
    expect(picker["data-controller"]).to eq("bridge--sections")
    row = picker.at_css("[data-bridge--sections-target='row']")
    expect(row["data-action"]).to eq("click->bridge--sections#open click->modal#open")
    items = picker.css("[data-bridge--sections-target='item']")
    expect(items.size).to eq(doc.css("[data-tabs-target='panel']").size)
    expect(items.first["data-section-group"]).to eq("Details")
    expect(items.last["data-section-danger"]).to eq("true")
    expect(items.last["data-section-group"]).to be_nil
  end
end

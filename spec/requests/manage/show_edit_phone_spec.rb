# frozen_string_literal: true

require "rails_helper"

# V1.1 plan Phase 2: a show's settings on a phone open on a list of
# sections you drill into, each with a way back and Save pinned to the bottom.
RSpec.describe "Show edit on a phone", type: :request do
  let(:password) { "Password123!" }
  let(:manager) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, owner: manager) }
  let(:production) { create(:production, organization: org) }
  let(:show) { create(:show, production: production) }

  before do
    create(:organization_role, :manager, user: manager, organization: org)
    post handle_signin_path, params: { email_address: manager.email_address, password: password }
    get manage_edit_show_path(production, show)
    expect(response).to have_http_status(:ok)
  end

  let(:doc) { Nokogiri::HTML(response.body) }

  it "opens on a drill-in list of every section" do
    expect(doc.at_css("[data-controller~='tabs']")["data-tabs-drill-value"]).to eq("true")
    list = doc.at_css("[data-show-edit-sections]")
    expect(list["data-tabs-target"]).to eq("list")
    labels = list.css("button").map { |b| b.text.squish }
    expect(labels.first).to eq("Basic Information")
    expect(labels).to include("Schedule", "Location", "Linked Events", "Danger Zone")
    expect(labels.size).to eq(doc.css("[data-tabs-target='panel']").size)
  end

  it "gives every section a way back and pins Save for the ones that save" do
    panels = doc.css("[data-tabs-target='panel']")
    panels.each do |panel|
      header = panel.at_css("[data-show-edit-section-header]")
      expect(header.at_css("button")["data-action"]).to eq("tabs#showList")
    end
    saving = panels.select { |p| p.at_css("[data-sticky-actions]") }
    expect(saving.map { |p| p.at_css("[data-show-edit-section-header]").text.squish }).to include("Sections / Basic Information", "Sections / Schedule")
    expect(panels.last.at_css("[data-sticky-actions]")).to be_nil # Danger Zone acts through its modals
    expect(doc.at_css("select[data-tabs-target='menu']")).to be_nil
  end
end

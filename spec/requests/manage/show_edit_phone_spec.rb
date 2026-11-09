# frozen_string_literal: true

require "rails_helper"

# A show's settings on a phone: the section row and its sheet, as on every
# settings page (Tim, 2026-11-08; it was a list you drilled into), and Save
# pinned to the bottom.
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

  it "opens every section from the section row's sheet" do
    tabs = doc.at_css("[data-controller~='tabs']")
    expect(tabs["data-tabs-drill-value"]).to be_nil
    picker = doc.at_css("[data-show-edit-sections] [data-section-picker]")
    expect(picker.at_css("button")["data-modal-id"]).to eq("show-edit-sections-sheet")
    expect(picker.at_css("[data-tabs-target='sectionLabel']").text.squish).to eq("Basic Information")
    items = doc.css("#show-edit-sections-sheet [data-tabs-target='sectionItem']")
    labels = items.map { |b| b.text.squish.delete_suffix(" Pro") }
    expect(labels.first).to eq("Basic Information")
    expect(labels).to include("Schedule", "Location", "Linked Events", "Danger Zone")
    expect(labels.size).to eq(doc.css("[data-tabs-target='panel']").size)
    expect(items.map { |b| b["data-action"] }.uniq).to eq([ "tabs#select modal#close" ])
  end

  it "pins Save for the sections that save, and has no list to go back to" do
    panels = doc.css("[data-tabs-target='panel']")
    expect(response.body).not_to include("tabs#showList")
    saving = panels.select { |p| p.at_css("[data-sticky-actions]") }
    expect(saving.size).to be >= 2
    expect(panels.first.at_css("[data-sticky-actions]")).to be_present
    expect(panels.last.at_css("[data-sticky-actions]")).to be_nil # Danger Zone acts through its modals
    expect(doc.at_css("select[data-tabs-target='menu']")).to be_nil
  end
end

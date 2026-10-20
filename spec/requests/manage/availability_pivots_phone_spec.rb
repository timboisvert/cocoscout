# frozen_string_literal: true

require "rails_helper"

# V1.1 plan Phase 2, availability pivots: on a phone the people × shows
# grids give way to a list of shows with counts (or a list of people), and
# the modals open as sheets. Desktop keeps the grids.
RSpec.describe "Availability pivots on a phone", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "The Late Show") }
  let!(:show) { create(:show, production: production, date_and_time: 1.week.from_now) }
  let!(:later_show) { create(:show, production: production, date_and_time: 2.weeks.from_now) }
  let(:abby) { create(:person, name: "Avail Abby") }
  let(:nate) { create(:person, name: "No-show Nate") }
  let(:quiet) { create(:person, name: "Quiet Quinn") }

  before do
    [ abby, nate, quiet ].each do |person|
      org.people << person
      create(:talent_pool_membership, talent_pool: production.talent_pool, member: person)
    end
    ShowAvailability.create!(show: show, available_entity: abby, status: :available)
    ShowAvailability.create!(show: show, available_entity: nate, status: :unavailable)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  describe "a production's availability" do
    before do
      get manage_casting_availability_path(production)
      expect(response).to have_http_status(:ok)
    end

    let(:doc) { Nokogiri::HTML(response.body) }

    it "lists the shows with available / no response / unavailable counts, each opening the show's modal" do
      rows = doc.css("[data-availability-shows-list] button")
      expect(rows.size).to eq(2)
      first = rows.first
      expect(first["data-modal-url"]).to eq(manage_show_modal_casting_availability_path(production, show))
      expect(first.css("[data-availability-counts] span[title]").map { |c| [ c["title"], c.text[/\d+/] ] })
        .to eq([ [ "Available", "1" ], [ "No response", "1" ], [ "Unavailable", "1" ] ])
    end

    it "lists the people too, each opening their modal" do
      rows = doc.css("[data-availability-people-list] button")
      expect(rows.map { |r| r["data-member-name"] }).to eq([ "Avail Abby", "No-show Nate", "Quiet Quinn" ])
      expect(rows.first.text).to include("Available for 1 of 2 shows")
      expect(rows.first["data-action"]).to eq("click->availability-modal#openMemberModal")
    end

    it "keeps the grid for desktop and opens the modals as sheets on a phone" do
      expect(doc.at_css("[data-availability-grid]")["class"]).to include("hidden sm:block")
      expect(doc.at_css("[data-availability-pivot]")["class"]).to include("sm:hidden")
      expect(doc.at_css("#availability-modal-content")["class"]).to include("max-sm:rounded-b-none")
      expect(doc.at_css("#member-availability-modal-content")["class"]).to include("max-sm:rounded-b-none")
    end
  end

  describe "the organization's availability" do
    it "lists the shows under their production with counts over that production's pool" do
      get manage_org_availability_path
      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)

      list = doc.at_css("[data-org-availability-list]")
      expect(list["class"]).to include("md:hidden")
      expect(list.text).to include("The Late Show")
      rows = list.css("button[data-show-id]")
      expect(rows.map { |r| r["data-show-id"] }).to eq([ show.id.to_s, later_show.id.to_s ])
      expect(rows.first["data-action"]).to eq("click->org-availability#openShowModal")
      expect(rows.first.css("[data-availability-counts] span[title]").map { |c| c.text[/\d+/] }).to eq([ "1", "1", "1" ])
      expect(doc.at_css("[data-org-availability-grid]")["class"]).to include("max-md:hidden")
    end

    it "opens the show's tabs as a sheet whose row actions come up from the bottom on a phone" do
      get manage_org_availability_show_modal_path(show), headers: { "X-Requested-With" => "XMLHttpRequest" }
      expect(response).to have_http_status(:ok)
      popup = Nokogiri::HTML(response.body).at_css("[data-availability-popup-sheet]")
      expect(popup["class"]).to include("max-md:!bottom-0", "max-md:rounded-t-2xl")
    end
  end
end

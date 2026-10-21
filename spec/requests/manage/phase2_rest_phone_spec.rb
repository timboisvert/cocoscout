# frozen_string_literal: true

require "rails_helper"

# V1.1 plan Phase 2, the rest: schedule auditions, casting select, Reports
# and the talent pool on a phone.
RSpec.describe "Phase 2 pages on a phone", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "The Late Show") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  describe "schedule auditions" do
    let(:cycle) { create(:audition_cycle, production: production) }
    let(:location) { create(:location, organization: org) }
    let!(:session) { create(:audition_session, audition_cycle: cycle, location: location) }
    let(:person) { create(:person, name: "Ava Available") }
    let!(:request_row) { create(:audition_request, audition_cycle: cycle, requestable: person) }
    let!(:audition) { create(:audition, audition_request: request_row, audition_session: session, auditionable: person) }

    it "opens Add and Review & notify as full-screen sheets, pins Review & notify, and gives Remove a real target" do
      get manage_schedule_auditions_signups_auditions_cycle_path(production, cycle)
      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      # Add is the shared People Picker (its own sheet); Review & notify keeps its full-screen sheet.
      expect(doc.at_css("[data-people-picker='audition-picker'] [data-sheet]")).to be_present
      expect(doc.at_css("[data-audition-notify-sheet]")["class"]).to include("max-sm:min-h-[100dvh]")
      bar = doc.at_css("[data-schedule-phone-bar]")
      expect(bar.at_css("button")["data-action"]).to eq("click->audition-notify#open")
      remove = doc.at_css("button[data-audition-id='#{audition.id}']")
      expect(remove["class"]).to include("w-7 h-7 sm:w-5 sm:h-5")
      expect(remove["aria-label"]).to eq("Remove from this session")
    end
  end

  describe "casting select" do
    let(:cycle) { create(:audition_cycle, production: production) }

    it "pins Done Selecting, and its sheet has the pink header and 44px decisions" do
      get manage_casting_select_signups_auditions_cycle_path(production, cycle)
      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      bar = doc.at_css("[data-casting-select-phone-bar]")
      expect(bar.text).to include("0 people added to cast", "Done Selecting")
      sheet = doc.at_css("[data-casting-select-sheet]")
      expect(sheet.at_css(".from-pink-500")).to be_present
      expect(sheet.at_css("[data-casting-drag-target='modalTitle']")["class"]).to include("text-white")
      expect(response.body).not_to include("bg-red-500 text-white")
    end
  end

  describe "Reports" do
    it "draws each row as a card on a phone and keeps the table for sm up and print" do
      get manage_report_revenue_by_production_path
      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      cards = doc.at_css("[data-report-cards]")
      expect(cards["class"]).to include("sm:hidden", "print:hidden")
      card = cards.at_css("[data-report-card]")
      expect(card.text).to include("The Late Show")
      expect(card.css("dt").map(&:text)).to eq([ "Events", "Tickets", "Revenue" ])
      expect(cards.at_css("[data-report-total-card]")).to be_present
      expect(doc.at_css("[data-report-table]")["class"]).to include("max-sm:hidden", "print:block")
    end
  end

  describe "the talent pool" do
    let(:person) { create(:person, name: "Pool Pia") }

    before do
      org.people << person
      create(:talent_pool_membership, talent_pool: production.talent_pool, member: person)
    end

    it "opens a tile's actions in a sheet on a phone, with Remove kept to hover on desktop" do
      get manage_casting_settings_section_path(production_id: production, section: "talent_pool")
      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      grid = doc.at_css("[data-controller='tile-sheet']")
      tile = grid.at_css("a[data-action='click->tile-sheet#open']")
      expect(tile["data-tile-name"]).to eq("Pool Pia")
      expect(tile["data-tile-remove"]).to eq("true")
      expect(tile["href"]).to eq(manage_person_path(person))
      expect(grid.at_css("button[data-action='talent-pool-inline#openRemoveModal']")["class"]).to include("max-sm:hidden")
      sheet = doc.at_css("#talent-pool-tile-sheet")
      expect(sheet.at_css("[data-tile-sheet-target='profileLink']")).to be_present
      expect(sheet.at_css("[data-tile-sheet-target='removeButton']")["data-action"]).to eq("click->modal#close talent-pool-inline#openRemoveModal")
      expect(doc.at_css("[data-people-picker='talent-pool-picker']")).to be_present # Add is the shared People Picker
      expect(doc.at_css("[data-talent-pool-remove-sheet]")["class"]).to include("max-sm:rounded-t-2xl")
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

# V1.1 plan Phase 2: the audition requests list on a phone has compact
# rows with vote chips, a sort and filter row (not voted by me, most yes
# first) and a Select mode for bulk archive.
RSpec.describe "Audition requests list on a phone", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org) }
  let(:cycle) { create(:audition_cycle, production: production, voting_enabled: true, active: true) }

  let!(:first) { create(:audition_request, audition_cycle: cycle, created_at: 3.days.ago, requestable: create(:person, name: "Early Ed")) }
  let!(:second) { create(:audition_request, audition_cycle: cycle, created_at: 2.days.ago, requestable: create(:person, name: "Middle Mo")) }
  let!(:third) { create(:audition_request, audition_cycle: cycle, created_at: 1.day.ago, requestable: create(:person, name: "Late Lou")) }

  before do
    AuditionRequestVote.create!(audition_request: second, user: owner, vote: :yes)
    AuditionRequestVote.create!(audition_request: third, user: create(:user), vote: :yes)
    AuditionRequestVote.create!(audition_request: third, user: create(:user), vote: :yes)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  def rows(params = {})
    get manage_signups_auditions_cycle_requests_path(production, cycle, params)
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body).css("[data-request-row]")
  end

  it "lists everyone in sign-up order with vote chips, and the filter row" do
    all = rows
    expect(all.map { |r| r.at_css("div.truncate").text.squish }).to eq([ "Early Ed", "Middle Mo", "Late Lou" ])
    chips = all.last.at_css("[data-vote-chips]")
    expect(chips.text.squish).to eq("2 yes 0 no 0 ?")
    expect(chips["class"]).to include("sm:hidden")
    filters = Nokogiri::HTML(response.body).at_css("[data-requests-filters]")
    expect(filters.at_css("[data-filter='unvoted']").text).to eq("Not voted by me (2)")
    expect(filters.at_css("[data-select-mode-button]")["data-action"]).to eq("click->bulk-select#toggleSelectMode")
  end

  it "filters to the ones I haven't voted on" do
    expect(rows(filter: "unvoted").map { |r| r.at_css("div.truncate").text.squish }).to eq([ "Early Ed", "Late Lou" ])
  end

  it "sorts by yes votes when asked, keeping sign-up order among ties" do
    expect(rows(sort: "most_yes").map { |r| r.at_css("div.truncate").text.squish }).to eq([ "Late Lou", "Middle Mo", "Early Ed" ])
  end

  it "hides the checkboxes on a phone until Select, and pins the archive bar there" do
    get manage_signups_auditions_cycle_requests_path(production, cycle)
    doc = Nokogiri::HTML(response.body)
    cell = doc.at_css("[data-bulk-select-target='selectCell']")
    expect(cell["class"]).to include("max-sm:hidden")
    expect(doc.at_css("[data-bulk-select-target='actionBar']")["class"]).to include("max-sm:fixed", "max-sm:bottom-0")
  end
end

# frozen_string_literal: true

require "rails_helper"

# The review card and the one vote bar (V1.1 plan §5 #18): every audition
# list draws a person the same way, and both voting pages share one bar.
RSpec.describe "The review card and the vote bar", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org) }
  let(:cycle) { create(:audition_cycle, production: production, voting_enabled: true, audition_voting_enabled: true, active: true) }
  let(:location) { create(:location, organization: org) }
  let!(:session) { create(:audition_session, audition_cycle: cycle, location: location) }
  let(:ava) { create(:person, name: "Ava Auditionee") }
  let!(:request_row) { create(:audition_request, audition_cycle: cycle, requestable: ava) }
  let!(:audition) { create(:audition, audition_request: request_row, audition_session: session, auditionable: ava, accepted_at: 1.day.ago) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "draws the requests list, the run-sheet and casting select's auditionees with it" do
    get manage_signups_auditions_cycle_requests_path(production, cycle)
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    card = doc.at_css("[data-review-card]")
    expect(card.text).to include("Ava Auditionee")
    expect(doc.at_css("[data-vote-chips]")).to be_present
    expect(doc.at_css("[data-vote-thirds]")["class"]).to include("hidden sm:grid")

    get manage_signups_auditions_cycle_session_path(production, cycle, session)
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    card = doc.at_css("[data-review-card]")
    expect(card.text).to include("Ava Auditionee", "RSVP'd Yes")
    expect(doc.at_css("[data-vote-chips]")).to be_present

    get manage_casting_select_signups_auditions_cycle_path(production, cycle)
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    cards = doc.css("[data-review-card]")
    expect(cards.size).to eq(2) # the list for a wide screen, the sheet for a phone
    expect(doc.css("[data-vote-thirds]").size).to eq(1)
    expect(doc.css("[data-vote-chips]").size).to eq(1)
    expect(doc.at_css("[data-casting-select-sheet] [data-review-card]")["class"]).to include("flex-1")
    expect(doc.at_css("[data-casting-select-sheet] [data-review-card]")["class"]).not_to include("sm:w-1/2")
  end

  it "shows the decision on casting select's cards" do
    pool = production.effective_talent_pool || create(:talent_pool, production: production)
    CastAssignmentStage.create!(talent_pool: pool, assignable: ava, decision_type: :cast, audition_cycle: cycle)
    get manage_casting_select_signups_auditions_cycle_path(production, cycle)
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(doc.css("[data-decision='cast']").size).to eq(2)
    expect(doc.css("[data-review-card]").map(&:text).join).to include("Added to cast")
  end

  it "votes from one bar on a request's page and on a session audition's page, in words" do
    get manage_signups_auditions_cycle_request_path(production, cycle, request_row)
    expect(response).to have_http_status(:ok)
    bar = Nokogiri::HTML(response.body).at_css("[data-audition-phone-vote-bar]")
    expect(bar["data-action"]).to include("touchstart->vote-form#touchStart")
    expect(bar.text).to include("Yes", "No", "Not sure", "left to vote on")
    expect(bar.css("[data-vote-form-vote-param='maybe']").size).to eq(2) # phone and wide

    get manage_signups_auditions_cycle_session_audition_path(production, cycle, session, audition)
    expect(response).to have_http_status(:ok)
    bar = Nokogiri::HTML(response.body).at_css("[data-audition-phone-vote-bar]")
    expect(bar).to be_present
    expect(bar.text).to include("Not sure", "talent pool")
    expect(bar.text).not_to include("left to vote on")
    expect(response.body).not_to match(/[\u{1F44D}\u{1F44E}\u{1F914}]/)
  end
end

# frozen_string_literal: true

require "rails_helper"

# V1.1 plan Phase 1b: voting on sign-ups from a phone. The vote bar names
# the next request I haven't voted on and how many are left.
RSpec.describe "Manage::AuditionRequests phone voting", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org) }
  let(:cycle) { create(:audition_cycle, production: production, voting_enabled: true, active: true) }

  let!(:first) { create(:audition_request, audition_cycle: cycle, created_at: 3.days.ago) }
  let!(:second) { create(:audition_request, audition_cycle: cycle, created_at: 2.days.ago) }
  let!(:third) { create(:audition_request, audition_cycle: cycle, created_at: 1.day.ago) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def page_for(request)
    get manage_signups_auditions_cycle_request_path(production, cycle, request)
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body)
  end

  describe "AuditionRequest#next_unvoted_for" do
    it "skips ones I voted on and wraps to the start of the cycle" do
      AuditionRequestVote.create!(audition_request: second, user: owner, vote: :yes)
      expect(first.next_unvoted_for(owner)).to eq(third)
      expect(third.next_unvoted_for(owner)).to eq(first)
    end

    it "is nil once I've voted on every other one, and ignores archived ones" do
      AuditionRequestVote.create!(audition_request: second, user: owner, vote: :yes)
      third.update!(archived_at: Time.current)
      expect(first.next_unvoted_for(owner)).to be_nil
    end
  end

  it "links to the next one I haven't voted on, with the count left" do
    AuditionRequestVote.create!(audition_request: second, user: owner, vote: :no)
    doc = page_for(first)

    row = doc.at_css("[data-next-unvoted]")
    expect(row.at_css("[data-unvoted-left]").text).to eq("2 left to vote on")
    link = row.at_css("a")
    expect(link.text).to include("Next I haven't voted on")
    expect(link["href"]).to eq(manage_signups_auditions_cycle_request_path(production, cycle, third))
  end

  it "says so when every one has a vote" do
    [ first, second, third ].each { |r| AuditionRequestVote.create!(audition_request: r, user: owner, vote: :maybe) }
    row = page_for(second).at_css("[data-next-unvoted]")
    expect(row.at_css("[data-unvoted-left]").text).to eq("You've voted on every one")
    expect(row.at_css("a")).to be_nil
  end

  it "uses words, not emoji, and swipe targets on the phone bar" do
    bar = page_for(second).at_css("[data-audition-phone-vote-bar]")
    expect(bar["data-action"]).to include("touchstart->vote-form#touchStart")
    expect(bar.at_css("[data-vote-form-target='previous']")["href"]).to end_with("/#{first.id}")
    expect(bar.at_css("[data-vote-form-target='next']")["href"]).to end_with("/#{third.id}")
    expect(bar.text).not_to match(/[\u{1F44D}\u{1F44E}\u{1F914}]/)
  end
end

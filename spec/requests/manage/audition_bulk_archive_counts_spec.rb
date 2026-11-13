# frozen_string_literal: true

require "rails_helper"

# Archiving sign-ups in bulk takes them off the "to review" counts at once
# (Tim, 2026-11-13: Home still said 18 after 11 were archived). The counts
# are cached by the sign-ups' latest change, and the bulk archive used to
# leave that untouched.
RSpec.describe "Archiving audition sign-ups in bulk", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:cycle) { create(:audition_cycle, production: production, opens_at: 1.week.ago, closes_at: 1.week.from_now) }
  let!(:requests) { travel_to(2.days.ago) { create_list(:audition_request, 3, audition_cycle: cycle) } }

  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "drops them from Home's count straight away" do
    get manage_path
    expect(response.body).to include("3 audition sign-ups to review")

    post manage_bulk_archive_signups_auditions_cycle_requests_path(production, cycle),
         params: { ids: requests.first(2).map(&:id), confirm_undecided: "1" }
    expect(cycle.audition_requests.active.count).to eq(1)

    get manage_path
    expect(response.body).to include("1 audition sign-up to review")
    expect(response.body).not_to include("3 audition sign-ups to review")
  end
end

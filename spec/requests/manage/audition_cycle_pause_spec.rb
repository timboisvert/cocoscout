# frozen_string_literal: true

require "rails_helper"

# Pausing auditions from the cycle's own page (Ronnie couldn't find how to
# stop Rising Stars taking applications, 2026-11-11). A pause leaves the
# dates alone: an open-ended cycle stays open-ended.
RSpec.describe "Manage::AuditionCycles pause and resume", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org) }
  let!(:cycle) { create(:audition_cycle, production: production, form_reviewed: true, opens_at: 1.week.ago, closes_at: nil, token: "PAUSETOKEN1") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "offers Pause auditions on an open cycle" do
    get manage_signups_auditions_path(production)

    expect(response.body).to include("Pause auditions")
    expect(response.body).not_to include("Resume auditions")
  end

  it "pauses without touching the dates, and offers Resume" do
    patch manage_pause_signups_auditions_cycle_path(production, cycle)

    expect(response).to redirect_to(manage_signups_auditions_path(production))
    expect(cycle.reload.timeline_status).to eq(:paused)
    expect(cycle.closes_at).to be_nil
    expect(cycle.accepting_requests?).to be(false)
    expect(AuditionCycle.currently_open).not_to include(cycle)

    get manage_signups_auditions_path(production)
    expect(response.body).to include("Resume auditions", "Paused")
  end

  it "takes no request while paused" do
    cycle.update!(paused_at: Time.current)

    expect {
      post my_submit_submit_audition_request_form_path(token: cycle.token), params: { question: {} }
    }.not_to change(AuditionRequest, :count)
    expect(response).to redirect_to(my_submit_audition_request_inactive_path(token: cycle.token))
  end

  it "resumes" do
    cycle.update!(paused_at: 1.hour.ago)

    patch manage_resume_signups_auditions_cycle_path(production, cycle)

    expect(cycle.reload.paused_at).to be_nil
    expect(cycle.accepting_requests?).to be(true)
  end
end

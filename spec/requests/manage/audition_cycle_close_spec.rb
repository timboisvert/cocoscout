# frozen_string_literal: true

require "rails_helper"

# Closing requests from the cycle's own page (Ronnie couldn't find how to stop
# Rising Stars taking applications, 2026-11-11).
RSpec.describe "Manage::AuditionCycles close and reopen", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org) }
  let!(:cycle) { create(:audition_cycle, production: production, form_reviewed: true, opens_at: 1.week.ago, closes_at: nil) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "offers Close requests on an open cycle" do
    get manage_signups_auditions_path(production)

    expect(response.body).to include("Close requests")
    expect(response.body).not_to include("Reopen requests")
  end

  it "closes requests now, and offers Reopen" do
    patch manage_close_signups_auditions_cycle_path(production, cycle)

    expect(response).to redirect_to(manage_signups_auditions_path(production))
    expect(cycle.reload.timeline_status).to eq(:closed)
    expect(cycle.accepting_requests?).to be(false)

    get manage_signups_auditions_path(production)
    expect(response.body).to include("Reopen requests")
  end

  it "reopens with no close date" do
    cycle.update!(closes_at: 1.hour.ago)

    patch manage_reopen_signups_auditions_cycle_path(production, cycle)

    expect(cycle.reload.closes_at).to be_nil
    expect(cycle.accepting_requests?).to be(true)
  end
end

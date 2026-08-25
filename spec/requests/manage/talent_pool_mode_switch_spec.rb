# frozen_string_literal: true

require "rails_helper"

# Switching an org to single-pool mode and back must round-trip cleanly.
# The 2026-08-25 incident: productions carried stale TalentPoolShares (to a
# legacy org-wide pool); the switch cycle only cleaned up shares to the
# CURRENT org pool, so the moment the org went back to per-production mode
# every stale share took over and everyone resolved to one huge pool.
RSpec.describe "Manage::TalentPools mode switching", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production_a) { create(:production, organization: org, name: "Alpha") }
  let!(:production_b) { create(:production, organization: org, name: "Bravo") }
  let(:person_a) { create(:person).tap { |p| org.people << p } }
  let(:person_b) { create(:person).tap { |p| org.people << p } }

  before do
    production_a.talent_pool.people << person_a
    production_b.talent_pool.people << person_b
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "supersedes a stale share on the way in, so switching back restores each production's own pool" do
    # A leftover share from an older setup: Bravo pointing at Alpha's pool
    TalentPoolShare.create!(production: production_b, talent_pool: production_a.talent_pool)
    expect(production_b.effective_talent_pool).to eq(production_a.talent_pool)

    post manage_casting_talent_pools_switch_to_single_path, params: { strategy: "merge_all" }
    expect(response).to redirect_to(manage_casting_talent_pools_path)
    org.reload
    expect(org.talent_pool_mode).to eq("single")

    post manage_casting_talent_pools_switch_to_per_production_path, params: { strategy: "restore" }
    org.reload
    expect(org.talent_pool_mode).to eq("per_production")

    # The stale share is gone — each production is back on its own pool,
    # memberships untouched
    expect(production_a.reload.effective_talent_pool).to eq(production_a.talent_pool)
    expect(production_b.reload.effective_talent_pool).to eq(production_b.talent_pool)
    expect(production_a.talent_pool.people).to contain_exactly(person_a)
    expect(production_b.talent_pool.people).to contain_exactly(person_b)
  end

  it "merge_all copies members into the org pool without touching production pools" do
    post manage_casting_talent_pools_switch_to_single_path, params: { strategy: "merge_all" }

    org_pool = org.reload.organization_talent_pool
    expect(org_pool.people).to contain_exactly(person_a, person_b)
    expect(production_a.talent_pool.people).to contain_exactly(person_a)
    expect(production_b.talent_pool.people).to contain_exactly(person_b)
  end
end

# frozen_string_literal: true

require "rails_helper"

# Regression (Pattern 1): scheduling a course from a contract created a NEW course
# production and moved the contract's shows onto it, leaving the contract's original
# production as an empty orphan. The wizard must reuse the contract's production.
RSpec.describe "Course wizard reuses a contract's production", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:location) { create(:location, organization: org) }

  let(:contract) { create(:contract, organization: org, status: :active) }
  # Simulate the post-activation state: the contract already has its production + show.
  let!(:contract_production) do
    create(:production, organization: org, name: "Rental Show", production_type: :third_party, contract: contract)
  end
  let!(:show) { create(:show, production: contract_production, location: location) }

  # The wizard stores its state in Rails.cache, which is :null_store in test —
  # swap in a real store so the seeded state survives the request.
  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = original
  end

  before do
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    Rails.cache.write(
      "course_offering_wizard:#{owner.id}:#{org.id}",
      {
        title: "Reused Course",
        price_cents: 5000,
        currency: "usd",
        registration_mode: "custom",
        schedule_mode: "contract",
        contract_id: contract.id,
        selected_show_ids: [ show.id ]
      },
      expires_in: 1.hour
    )
  end

  it "does NOT create a second production for the contract" do
    expect {
      post manage_course_wizard_create_path
    }.not_to change { Production.where(contract_id: contract.id).count }

    contract.reload
    expect(contract.productions.count).to eq(1)
    reused = contract.productions.first
    expect(reused.id).to eq(contract_production.id)
    expect(reused.production_type).to eq("course")
    expect(reused.course_offerings.count).to eq(1)
    # The show stayed on the (single) production and became a class session.
    expect(show.reload.production_id).to eq(reused.id)
  end
end

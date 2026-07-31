# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Deleting a cancelled contract removes its empty course run", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  let!(:production) { create(:production, organization: org, production_type: :course) }
  let!(:contract) { create(:contract, organization: org, status: :cancelled, production: production) }
  let!(:offering) { create(:course_offering, production: production, contract: contract) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "removes the run and its now-empty production" do
    delete manage_contract_path(contract)
    expect(CourseOffering.exists?(offering.id)).to be false
    expect(Production.exists?(production.id)).to be false
  end

  it "keeps a run that has confirmed registrations" do
    create(:course_registration, course_offering: offering, amount_cents: 5000, status: "confirmed")
    delete manage_contract_path(contract)
    expect(CourseOffering.exists?(offering.id)).to be true
    expect(Production.exists?(production.id)).to be true
  end

  it "keeps the durable course when it still has another run" do
    other_run = create(:course_offering, production: production) # not tied to this contract
    delete manage_contract_path(contract)
    expect(CourseOffering.exists?(offering.id)).to be false  # tied run removed
    expect(CourseOffering.exists?(other_run.id)).to be true  # other run survives
    expect(Production.exists?(production.id)).to be true      # course survives
  end
end

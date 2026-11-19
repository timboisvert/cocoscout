# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Superadmin deletes an organization", type: :request do
  let(:password) { "Password123!" }
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let(:organization) { create(:organization) }
  let(:production) { create(:production, organization: organization) }

  before do
    post handle_signin_path, params: { email_address: superadmin.email_address, password: password }
  end

  it "deletes the organization with its productions, dates, locations, and casting" do
    location = create(:location, organization: organization)
    show = create(:show, production: production, location: location)
    audition_cycle = create(:audition_cycle, production: production)
    talent_pool = create(:talent_pool, production: production)
    role = create(:role, show: show)
    CastAssignmentStage.create!(audition_cycle: audition_cycle, talent_pool: talent_pool, assignable: role)

    delete destroy_organization_path(organization)

    expect(response).to redirect_to(organizations_list_path)
    expect(Organization.exists?(organization.id)).to be false
    expect(Production.exists?(production.id)).to be false
    expect(CastAssignmentStage.where(audition_cycle_id: audition_cycle.id)).to be_empty
  end
end

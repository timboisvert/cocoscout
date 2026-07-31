# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::CourseOfferings instructor payout split", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "course") }
  let!(:offering) { create(:course_offering, production: production) }
  let!(:instructor) { create(:person) }
  let!(:coi) { offering.course_offering_instructors.create!(person: instructor) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "saves a percentage split" do
    post manage_course_offering_update_instructor_path(offering), params: {
      instructor_person_ids: [ instructor.id ],
      instructor_payout_types: { instructor.id.to_s => "percentage" },
      instructor_payout_values: { instructor.id.to_s => "60" }
    }
    coi.reload
    expect(coi.payout_type).to eq("percentage")
    expect(coi.payout_percentage).to eq(60)
    expect(coi.payout_cents).to be_nil
  end

  it "saves a flat split, converting dollars to cents" do
    post manage_course_offering_update_instructor_path(offering), params: {
      instructor_person_ids: [ instructor.id ],
      instructor_payout_types: { instructor.id.to_s => "flat" },
      instructor_payout_values: { instructor.id.to_s => "250" }
    }
    coi.reload
    expect(coi.payout_type).to eq("flat")
    expect(coi.payout_cents).to eq(25000)
    expect(coi.payout_percentage).to be_nil
  end
end

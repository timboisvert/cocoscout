# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::CourseOfferings delete", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "course") }
  let!(:offering) { create(:course_offering, production: production) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "refuses to delete a course with registrations, and says why" do
    create(:course_registration, course_offering: offering, status: "confirmed")

    delete manage_delete_course_offering_path(offering)

    expect(CourseOffering.exists?(offering.id)).to be(true)
    expect(flash[:alert]).to match(/registrations/i)
  end

  it "deletes an empty course and its now-empty production" do
    delete manage_delete_course_offering_path(offering)

    expect(CourseOffering.exists?(offering.id)).to be(false)
    expect(Production.exists?(production.id)).to be(false)
    expect(flash[:notice]).to match(/deleted/i)
  end
end

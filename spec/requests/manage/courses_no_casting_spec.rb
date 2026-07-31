# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Courses have no casting management", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:course) { create(:production, organization: org, production_type: "course") }
  let(:in_house) { create(:production, organization: org, production_type: "in_house") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "redirects a course away from Manage Casting" do
    get manage_casting_production_path(course)
    expect(response).to redirect_to(manage_course_offerings_path)
  end

  it "redirects a course away from Manage Availability" do
    get manage_casting_availability_path(course)
    expect(response).to redirect_to(manage_course_offerings_path)
  end

  it "still allows casting for a non-course production" do
    get manage_casting_production_path(in_house)
    expect(response).not_to redirect_to(manage_course_offerings_path)
  end
end

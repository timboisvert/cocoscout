# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::CourseOfferings index payouts overview", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "course") }
  let!(:offering) { create(:course_offering, production: production, price_cents: 4000) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "surfaces a course with revenue as awaiting payout, linking to its payout page" do
    create(:course_registration, course_offering: offering, amount_cents: 4000, status: "confirmed")

    get manage_course_offerings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Awaiting payout")
    expect(response.body).to include("Courses awaiting payout")
    expect(response.body).to include(manage_course_offering_payout_path(offering))
    expect(response.body).to include("Set up your bank")
  end

  it "does not list a course with no revenue as awaiting payout" do
    get manage_course_offerings_path

    expect(response.body).not_to include("Courses awaiting payout")
  end

  it "excludes completed runs from Active and shows them as Completed" do
    offering.update!(status: :open)
    create(:course_offering, production: production, status: :completed)

    get manage_course_offerings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Completed")       # badge renders
    expect(CourseOffering.active).to contain_exactly(offering) # completed excluded from active
  end

  it "does not list a course whose payout is marked paid (e.g. settled offline)" do
    create(:course_registration, course_offering: offering, amount_cents: 4000, status: "confirmed")
    CourseOfferingPayout.create!(course_offering: offering, status: "paid", paid_at: Time.current)

    get manage_course_offerings_path

    expect(response.body).not_to include("Courses awaiting payout")
  end

  it "leads with a module hub header instead of top-nav links" do
    get manage_course_offerings_path

    # The hub's two entry points, as action cards with descriptions.
    expect(response.body).to include("Add a Course")
    expect(response.body).to include("Course Settings")
    expect(response.body).to include(manage_course_wizard_start_path)
    expect(response.body).to include(manage_course_settings_path)
    # The old pink top-nav link label is gone.
    expect(response.body).not_to include("Payout Settings")
  end
end

# frozen_string_literal: true

require "rails_helper"

# A course's public page in the storefront's layout A: the price all in (tap
# it for the course and its tax), spots left, when and where, and the step to
# register around the account students keep.
RSpec.describe "Course page", type: :request do
  let(:org) { create(:organization, name: "Stars & Garters") }
  let(:production) { create(:production, organization: org, name: "Improv 101") }
  let(:location) { create(:location, organization: org, name: "The Annex", address1: "1 Main St", city: "Chicago", state: "IL") }
  let!(:offering) { create(:course_offering, production: production, title: "Improv 101", price_cents: 10_000, capacity: 12) }
  let!(:first_session) { create(:show, production: production, course_offering: offering, event_type: "class", date_and_time: Time.zone.local(2026, 11, 3, 19, 0), duration_minutes: 120, location: location) }
  let!(:second_session) { create(:show, production: production, course_offering: offering, event_type: "class", date_and_time: Time.zone.local(2026, 11, 10, 19, 0), duration_minutes: 120, location: location) }

  before do
    travel_to Time.zone.local(2026, 10, 4, 12, 0)
    TicketTaxSetting.save!(org, kind: "courses", name: "Sales tax", percent: "8", mode: "added")
    9.times { create(:course_registration, course_offering: offering, status: "confirmed") }
  end

  it "shows a visitor the course, the all-in price, spots left, when and where, and the account step" do
    get "/c/#{offering.short_code}"
    expect(response).to redirect_to(my_course_entry_path(code: offering.short_code))
    follow_redirect!

    expect(response.body).to include("Improv 101", "Stars &amp; Garters", "Starts Tuesday, November 3 · 7:00 – 9:00 PM", "2 sessions",
                                     "The Annex", "Directions", "$108.00", "incl. sales tax 8%", ">Course<", "$100.00", ">Sales tax 8%<", "$8.00",
                                     "Only 3 spots left", "Create your account to register", "Already have one?", "Class registration by CocoScout")
    expect(response.body).not_to include("Registering as", "google.com/maps?q=")
  end

  it "shows a signed-in person who they're registering as and a Register button with the price" do
    user = create(:user, password: "Password123!")
    post handle_signin_path, params: { email_address: user.email_address, password: "Password123!" }
    get my_course_show_path(code: offering.short_code)
    expect(response.body).to include("Registering as", user.person.name, "Register · $108.00", "Not you?")
    expect(response.body).not_to include("Create your account")
  end

  it "says why when the course can't take registrations" do
    3.times { create(:course_registration, course_offering: offering, status: "confirmed") }
    get my_course_entry_path(code: offering.short_code)
    expect(response.body).to include("This course is full")
    expect(response.body).not_to include("Create your account")
  end
end

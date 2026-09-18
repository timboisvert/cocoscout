# frozen_string_literal: true

require "rails_helper"

RSpec.describe "My work availability", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user) }
  let(:day) { Date.current.next_occurring(:thursday) + 7 }

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  describe "the page" do
    it "shows the usual week, the exceptions and the calendar" do
      get my_work_availability_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Your usual week").and include("Exceptions")
      expect(response.body).to include("Monday").and include("Sunday")
      expect(response.body).to include("Only certain hours")
      # The morph + scroll-keeping meta, so saving doesn't jump to the top.
      expect(response.body).to include('name="turbo-refresh-method" content="morph"')
    end

    it "shows what's been said" do
      StaffAvailabilityWriter.new(person).set_weekdays!([ 1 ], state: "hours", windows: [ { from: "17:00", to: "00:00" } ])
      StaffAvailabilityWriter.new(person).save_exception!(starts_on: day, ends_on: day + 3, state: "off", note: "Lisbon")

      get my_work_availability_path

      expect(response.body).to include("After 5:00 PM")
      expect(response.body).to include("Lisbon")
      expect(response.body).to include("Confirmed through")
    end
  end

  describe "setting the usual week" do
    it "saves one answer for every day ticked and comes back" do
      patch my_work_availability_week_path, params: {
        days: %w[1 2], state: "hours", windows: { "0" => { from: "18:00", to: "23:00" } }
      }

      expect(response).to redirect_to(my_work_availability_path)
      expect(flash[:notice]).to eq("Saved your usual Monday and Tuesday.")
      labels = WorkAvailabilityPicture.new(person).week.index_by(&:wday).transform_values { |d| d.answer.label }
      expect(labels.values_at(1, 2, 3)).to eq([ "6:00 PM – 11:00 PM", "6:00 PM – 11:00 PM", "Anytime" ])
    end

    it "says what's wrong instead of saving nonsense" do
      patch my_work_availability_week_path, params: { days: %w[1], state: "hours" }

      expect(response).to redirect_to(my_work_availability_path)
      expect(flash[:alert]).to include("hours you can work")
      expect(person.staff_availability_entries).to be_empty
    end
  end

  describe "exceptions" do
    it "adds one, changes it, and removes it" do
      post my_work_availability_exceptions_path, params: { starts_on: day.iso8601, state: "off", note: "Wedding" }
      expect(person.staff_availability_entries.dated.pluck(:starts_on, :ends_on, :note).uniq).to eq([ [ day, day, "Wedding" ] ])

      post my_work_availability_exceptions_path, params: {
        starts_on: day.iso8601, ends_on: (day + 1).iso8601, state: "anytime",
        replacing_starts_on: day.iso8601, replacing_ends_on: day.iso8601
      }
      expect(person.staff_availability_entries.dated.pluck(:starts_on, :ends_on, :polarity).uniq)
        .to eq([ [ day, day + 1, "available" ] ])

      delete my_work_availability_exceptions_path, params: { starts_on: day.iso8601, ends_on: (day + 1).iso8601 }
      expect(person.staff_availability_entries).to be_empty
    end
  end

  describe "confirming" do
    it "vouches for the coming weeks and goes back to My Shifts" do
      post my_confirm_work_availability_path

      expect(person.reload.availability_confirmed_through).to eq(Date.current + StaffAvailabilityWriter::CONFIRM_DAYS)
      expect(response).to redirect_to(my_shifts_path)
    end

    it "goes back to onboarding when that's where they came from" do
      org = create(:organization)
      create(:organization_staff_member, organization: org, person: person)

      post my_confirm_work_availability_path(onboarding: org.id)

      expect(response).to redirect_to(my_onboarding_path(org.id, availability_done: 1))
    end

    it "won't send them to an org they don't staff" do
      stranger = create(:organization)

      post my_confirm_work_availability_path(onboarding: stranger.id)

      expect(response).to redirect_to(my_shifts_path)
    end
  end

  it "fills in the My Shifts card" do
    org = create(:organization)
    create(:organization_staff_member, organization: org, person: person)
    StaffAvailabilityWriter.new(person).set_weekdays!([ 1, 2, 3, 4 ], state: "off")

    get my_shifts_path

    expect(response.body).to include("Mon – Thu").and include("Not working")
    expect(response.body).to include(my_work_availability_path)
  end
end

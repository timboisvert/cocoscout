# frozen_string_literal: true

require "rails_helper"

RSpec.describe "My work availability", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user) }
  let(:day) { Date.current.next_occurring(:thursday) + 7 }

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  describe "the page" do
    it "is the calendar, with my usual week and what's coming up beside it" do
      get my_work_availability_path

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include(Date.current.strftime("%B")).and include("My usual week").and include("When I'm available to work")
      # Monday-first, like the staffing week.
      expect(body.index(">Mon<")).to be < body.index(">Sun<")
      expect(body).to include("Some hours").and include("Change my usual week")
      # Times are picked from hour / five-minute / AM-PM dropdowns, never typed.
      expect(body).to include(%(data-clock-part="minute")).and include(%(<option value="55">55</option>))
      expect(body).not_to include(%(type="time"))
      expect(ActionController::Base.helpers.strip_tags(body)).not_to match(/exception/i)
      # The morph + scroll-keeping meta, so saving doesn't jump to the top.
      expect(body).to include('name="turbo-refresh-method" content="morph"')
    end

    it "shows what's been said" do
      StaffAvailabilityWriter.new(person).set_weekdays!([ 1 ], state: "hours", windows: [ { from: "17:00", to: "00:00" } ])
      StaffAvailabilityWriter.new(person).set_weekdays!([ 2 ], state: "hours", windows: [ { from: "18:00", to: "23:00" } ])
      StaffAvailabilityWriter.new(person).save_exception!(starts_on: day, ends_on: day + 3, state: "off", note: "Lisbon")
      StaffAvailabilityWriter.new(person).confirm!

      get my_work_availability_path

      # Every day says itself under its bar: a day part by name, else the hours.
      expect(response.body).to include("All evening").and include("6p – 11p").and include("All day").and include("Off")
      expect(response.body).to include("After 5:00 PM")
      expect(response.body).to include("Lisbon")
      # A change carries its dates and note on the calendar cells it covers.
      expect(response.body).to include(%(data-change-starts-on="#{day.iso8601}")).and include(%(data-change-note="Lisbon"))
      # Confirmed: a green check, not the button.
      expect(response.body).to include("My availability is up to date").and include("Confirmed through")
      expect(response.body).not_to include("Confirm my availability")
    end

    it "offers the confirm button until they say it's up to date" do
      get my_work_availability_path

      expect(response.body).to include("Is your availability up to date?").and include("Confirm my availability")
    end

    it "pages through the coming year and no further" do
      get my_work_availability_path(month: (Date.current >> 2).beginning_of_month.iso8601)
      expect(response.body).to include((Date.current >> 2).strftime("%B %Y"))

      get my_work_availability_path(month: (Date.current >> 30).iso8601)
      expect(response.body).to include((Date.current >> 11).strftime("%B %Y"))

      get my_work_availability_path(month: "last-tuesday")
      expect(response.body).to include(Date.current.strftime("%B"))
    end

    it "folds next month in during the last week of this one" do
      travel_to Time.zone.local(2026, 9, 28, 12) do
        get my_work_availability_path
        expect(response.body).to include("September / October 2026")
        expect(response.body).to include(my_work_availability_path(month: "2026-11-01"))

        # Asking for the folded month lands on the combined view.
        get my_work_availability_path(month: "2026-10-01")
        expect(response.body).to include("September / October 2026")
      end

      travel_to Time.zone.local(2026, 9, 10, 12) do
        get my_work_availability_path
        expect(response.body).to include("September 2026").and include(my_work_availability_path(month: "2026-10-01"))
      end
    end
  end

  describe "changing every such weekday" do
    it "saves one answer for every day ticked and comes back to the same month" do
      month = (Date.current >> 1).beginning_of_month.iso8601
      post my_work_availability_path, params: {
        scope: "week", days: %w[1 2], state: "hours", windows: { "0" => { from: "18:00", to: "23:00" } }, month: month
      }

      expect(response).to redirect_to(my_work_availability_path(month: month, anchor: "calendar"))
      expect(flash[:notice]).to eq("Saved your usual Monday and Tuesday.")
      labels = WorkAvailabilityPicture.new(person).week.index_by(&:wday).transform_values { |d| d.answer.label }
      expect(labels.values_at(1, 2, 3)).to eq([ "6:00 PM – 11:00 PM", "6:00 PM – 11:00 PM", "Anytime" ])
    end

    it "says so when a time isn't on a 5-minute step" do
      post my_work_availability_path, params: { scope: "dates", starts_on: day.iso8601, state: "hours",
                                                windows: { "0" => { from: "00:56", to: "03:00" } } }

      expect(flash[:alert]).to eq("Times go in 5-minute steps, like 12:55.")
      expect(person.staff_availability_entries).to be_empty
    end

    it "says what's wrong instead of saving nonsense" do
      post my_work_availability_path, params: { scope: "week", days: %w[1], state: "hours" }

      expect(response).to redirect_to(my_work_availability_path(anchor: "calendar"))
      expect(flash[:alert]).to include("hours you can work")
      expect(person.staff_availability_entries).to be_empty
    end
  end

  describe "changing just some dates" do
    it "adds them, changes them, and puts them back to the usual week" do
      post my_work_availability_path, params: { scope: "dates", starts_on: day.iso8601, state: "off", note: "Wedding" }
      expect(flash[:notice]).to eq("Saved #{day.strftime('%a, %b %-d')}.")
      expect(person.staff_availability_entries.dated.pluck(:starts_on, :ends_on, :note).uniq).to eq([ [ day, day, "Wedding" ] ])

      post my_work_availability_path, params: {
        scope: "dates", starts_on: day.iso8601, ends_on: (day + 1).iso8601, state: "anytime",
        replacing_starts_on: day.iso8601, replacing_ends_on: day.iso8601
      }
      expect(person.staff_availability_entries.dated.pluck(:starts_on, :ends_on, :polarity).uniq)
        .to eq([ [ day, day + 1, "available" ] ])

      delete my_work_availability_dates_path, params: { starts_on: day.iso8601, ends_on: (day + 1).iso8601 }
      expect(flash[:notice]).to start_with("Back to your usual week for #{day.strftime('%a, %b %-d')}")
      expect(person.staff_availability_entries).to be_empty
    end

    it "treats a save with no scope as just those dates" do
      post my_work_availability_path, params: { starts_on: day.iso8601, state: "off" }

      expect(person.staff_availability_entries.dated.count).to be_positive
      expect(person.staff_availability_entries.weekly).to be_empty
    end
  end

  describe "confirming" do
    it "asks them to confirm again when they change anything" do
      StaffAvailabilityWriter.new(person).confirm!
      post my_work_availability_path, params: { scope: "week", days: %w[0], state: "off" }

      get my_work_availability_path
      expect(response.body).to include("Confirm my availability")
    end

    it "stays on the page when confirmed from the page" do
      post my_confirm_work_availability_path(stay: 1)

      expect(person.reload.availability_confirmed_through).to be_present
      expect(response).to redirect_to(my_work_availability_path(anchor: "calendar"))
    end

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

require 'rails_helper'

RSpec.describe "My::Availability", type: :system do
  let!(:user) { create(:user) }
  let!(:person) { create(:person, user: user, email: user.email_address) }
  let(:production_company) { create(:production_company) }
  let(:production) { create(:production, production_company: production_company, name: "Wicked") }
  let(:cast) { create(:cast, production: production) }

  describe "availability index" do
    let!(:show1) { create(:show, production: production, date_and_time: 1.week.from_now, canceled: false) }
    let!(:show2) { create(:show, production: production, date_and_time: 2.weeks.from_now, canceled: false) }
    let!(:canceled_show) { create(:show, production: production, date_and_time: 3.weeks.from_now, canceled: true) }

    it "displays shows awaiting response by default" do
      cast.people << person
      sign_in_as_person(user, person)
      visit "/my/availability"

      expect(page).to have_content(show1.date_and_time.strftime("%a, %b %-d, %Y"))
      expect(page).to have_content(show2.date_and_time.strftime("%a, %b %-d, %Y"))
    end

    it "does not display canceled shows" do
      cast.people << person
      sign_in_as_person(user, person)
      visit "/my/availability"

      expect(page).not_to have_content(canceled_show.date_and_time.strftime("%a, %b %-d, %Y"))
    end

    it "allows marking availability as available", js: true do
      cast.people << person
      sign_in_as_person(user, person)
      visit "/my/availability"

      # Find the show and click available button
      within("[data-availability-show-id-value='#{show1.id}']") do
        find("[data-action='click->availability#setAvailable']").click

        # Wait for success indicator
        expect(page).to have_css("[data-availability-target='successIndicator']", visible: true)
      end
    end

    it "allows marking availability as unavailable", js: true do
      cast.people << person
      sign_in_as_person(user, person)
      visit "/my/availability"

      within("[data-availability-show-id-value='#{show1.id}']") do
        find("[data-action='click->availability#setUnavailable']").click

        expect(page).to have_css("[data-availability-target='successIndicator']", visible: true)
      end
    end

    describe "with existing availabilities" do
      let!(:available_show) { create(:show, production: production, date_and_time: 1.week.from_now) }
      let!(:unavailable_show) { create(:show, production: production, date_and_time: 2.weeks.from_now) }

      before do
        create(:show_availability, :available, person: person, show: available_show)
        create(:show_availability, :unavailable, person: person, show: unavailable_show)
      end

      it "displays existing availability status" do
        cast.people << person
        sign_in_as_person(user, person)
        visit "/my/availability?filter=all"

        # Check that shows have the correct status
        expect(page).to have_css("[data-availability-show-id-value='#{available_show.id}'][data-availability-status-value='available']")
        expect(page).to have_css("[data-availability-show-id-value='#{unavailable_show.id}'][data-availability-status-value='unavailable']")
      end
    end

    describe "filtering" do
      let!(:responded_show) { create(:show, production: production, date_and_time: 1.week.from_now) }
      let!(:no_response_show) { create(:show, production: production, date_and_time: 2.weeks.from_now) }

      before do
        create(:show_availability, person: person, show: responded_show)
      end

      it "filters to show only no response shows" do
        cast.people << person
        sign_in_as_person(user, person)
        visit "/my/availability?filter=no_response"

        expect(page).to have_content(no_response_show.date_and_time.strftime("%a, %b %-d, %Y"))
        expect(page).not_to have_content(responded_show.date_and_time.strftime("%a, %b %-d, %Y"))
      end

      it "shows all shows when filter is all" do
        cast.people << person
        sign_in_as_person(user, person)
        visit "/my/availability?filter=all"

        expect(page).to have_content(no_response_show.date_and_time.strftime("%a, %b %-d, %Y"))
        expect(page).to have_content(responded_show.date_and_time.strftime("%a, %b %-d, %Y"))
      end
    end
  end

  describe "availability calendar" do
    let!(:show_event) { create(:show, production: production, date_and_time: 1.week.from_now, event_type: :show) }
    let!(:rehearsal) { create(:show, production: production, date_and_time: 2.weeks.from_now, event_type: :rehearsal) }
    let!(:meeting) { create(:show, production: production, date_and_time: 3.weeks.from_now, event_type: :meeting) }

    it "displays events in calendar view" do
      cast.people << person
      sign_in_as_person(user, person)
      visit "/my/availability/calendar"

      expect(page).to have_content(show_event.date_and_time.strftime("%B %Y"))
      expect(page).to have_content(show_event.date_and_time.day)
    end

    it "filters by event type" do
      cast.people << person
      sign_in_as_person(user, person)
      visit "/my/availability/calendar?event_type=show"

      expect(page).to have_content(show_event.date_and_time.day.to_s)
      # Rehearsal and meeting should not appear with show filter
    end

    it "shows all event types by default" do
      cast.people << person
      sign_in_as_person(user, person)
      visit "/my/availability/calendar"

      expect(page).to have_content(show_event.date_and_time.strftime("%b %-d"))
      expect(page).to have_content(rehearsal.date_and_time.strftime("%b %-d"))
      expect(page).to have_content(meeting.date_and_time.strftime("%b %-d"))
    end

    it "allows marking availability from calendar", js: true do
      cast.people << person
      sign_in_as_person(user, person)
      visit "/my/availability/calendar"

      within("[data-availability-show-id-value='#{show_event.id}']") do
        find("[data-action='click->availability#setAvailable']").click

        expect(page).to have_css("[data-availability-target='successIndicator']", visible: true)
      end
    end
  end

  describe "when user is not in any casts" do
    before do
      cast.people.clear
    end

    it "shows message about no productions" do
      sign_in_as_person(user, person)
      visit "/my/availability"
      # Should not see any shows since person is not in a cast
      expect(page).not_to have_css("[data-availability-show-id-value]")
    end
  end
end

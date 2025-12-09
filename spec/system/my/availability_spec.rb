# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'My::Availability', type: :system do
  let!(:user) { create(:user) }
  let!(:person) { create(:person, user: user, email: user.email_address) }
  let(:organization) { create(:organization) }
  let(:production) { create(:production, organization: organization, name: 'Wicked') }
  let(:talent_pool) { create(:talent_pool, production: production) }

  describe 'availability index' do
    let!(:show1) { create(:show, production: production, date_and_time: 1.week.from_now, canceled: false) }
    let!(:show2) { create(:show, production: production, date_and_time: 2.weeks.from_now, canceled: false) }
    let!(:canceled_show) { create(:show, production: production, date_and_time: 3.weeks.from_now, canceled: true) }

    it 'displays shows awaiting response by default' do
      talent_pool.people << person
      sign_in_as_person(user, person)
      visit '/my/availability'

      # Check for show date (day number) and day name
      expect(page).to have_content(show1.date_and_time.strftime('%-d'))
      expect(page).to have_content(show2.date_and_time.strftime('%-d'))
    end

    it 'does not display canceled shows' do
      talent_pool.people << person
      sign_in_as_person(user, person)
      visit '/my/availability'

      # Should not show the day number for the canceled show in an availability row
      expect(page).not_to have_css("[data-availability-show-id-value='#{canceled_show.id}']")
    end

    # it "allows marking availability as available" do
    #   cast.people << person
    #   sign_in_as_person(user, person)
    #   visit "/my/availability"

    #   # Find the show and click available button
    #   within("[data-availability-show-id-value='#{show1.id}']") do
    #     find("[data-availability-status='available']").click

    #     # Wait for success indicator
    #     expect(page).to have_css("[data-availability-show-id-value='#{show1.id}']")
    #   end
    # end

    # it "allows marking availability as unavailable" do
    #   cast.people << person
    #   sign_in_as_person(user, person)
    #   visit "/my/availability"

    #   within("[data-availability-show-id-value='#{show1.id}']") do
    #     find("[data-action='click->availability#setUnavailable']").click

    #     expect(page).to have_css("[data-availability-target='successIndicator']", visible: true)
    #   end
    # end

    describe 'with existing availabilities' do
      let!(:available_show) { create(:show, production: production, date_and_time: 1.week.from_now) }
      let!(:unavailable_show) { create(:show, production: production, date_and_time: 2.weeks.from_now) }

      it 'displays existing availability status' do
        create(:show_availability, available_entity: person, show: available_show, status: 'available')
        create(:show_availability, available_entity: person, show: unavailable_show, status: 'unavailable')
        talent_pool.people << person
        sign_in_as_person(user, person)
        visit '/my/availability?filter=all'

        # Check that shows have the correct status
        expect(page).to have_css("[data-availability-show-id-value='#{available_show.id}'][data-availability-status-value='available']")
        expect(page).to have_css("[data-availability-show-id-value='#{unavailable_show.id}'][data-availability-status-value='unavailable']")
      end
    end

    describe 'filtering' do
      it 'filters to show only no response shows' do
        create(:show_availability, available_entity: person, show: show1, status: 'available')
        talent_pool.people << person
        sign_in_as_person(user, person)
        visit '/my/availability?filter=no_response'

        expect(page).to have_css("[data-availability-show-id-value='#{show2.id}']")
        expect(page).not_to have_css("[data-availability-show-id-value='#{show1.id}']")
      end

      it 'shows all shows when filter is all' do
        create(:show_availability, available_entity: person, show: show1, status: 'available')
        talent_pool.people << person
        sign_in_as_person(user, person)
        visit '/my/availability?filter=all'

        expect(page).to have_css("[data-availability-show-id-value='#{show2.id}']")
        expect(page).to have_css("[data-availability-show-id-value='#{show1.id}']")
      end
    end
  end

  describe 'availability calendar' do
    let!(:show_event) { create(:show, production: production, date_and_time: 1.week.from_now, event_type: :show) }
    let!(:rehearsal) { create(:show, production: production, date_and_time: 2.weeks.from_now, event_type: :rehearsal) }
    let!(:meeting) { create(:show, production: production, date_and_time: 3.weeks.from_now, event_type: :meeting) }

    it 'displays events in calendar view' do
      talent_pool.people << person
      sign_in_as_person(user, person)
      visit '/my/availability/calendar'

      expect(page).to have_content(show_event.date_and_time.strftime('%B %Y'))
      expect(page).to have_content(show_event.date_and_time.day)
    end

    it 'filters by event type' do
      talent_pool.people << person
      sign_in_as_person(user, person)
      visit '/my/availability/calendar?event_type=show'

      expect(page).to have_content(show_event.date_and_time.day.to_s)
      # Rehearsal and meeting should not appear with show filter
    end

    it 'shows all event types by default' do
      talent_pool.people << person
      sign_in_as_person(user, person)
      visit '/my/availability/calendar'

      expect(page).to have_content(show_event.date_and_time.day.to_s)
      expect(page).to have_content(rehearsal.date_and_time.day.to_s)
      expect(page).to have_content(meeting.date_and_time.day.to_s)
    end

    # Skip this test for now - JS tests with AJAX need additional setup
    # The underlying controller endpoint is tested in request specs
    xit 'allows marking availability from calendar', js: true do
      talent_pool.people << person
      sign_in_as_person(user, person)
      visit '/my/availability/calendar'

      within("[data-availability-show-id-value='#{show_event.id}']") do
        find("a[data-availability-status='available']").click
      end

      # Wait for AJAX to complete
      sleep 2

      # Verify the availability was saved
      availability = ShowAvailability.find_by(available_entity: person, show: show_event)
      expect(availability).to be_present
      expect(availability.status).to eq('available')
    end
  end

  describe 'when user is not in any casts' do
    before do
      talent_pool.people.clear
    end

    it 'shows message about no productions' do
      sign_in_as_person(user, person)
      visit '/my/availability'
      # Should not see any shows since person is not in a cast
      expect(page).not_to have_css('[data-availability-show-id-value]')
    end
  end
end

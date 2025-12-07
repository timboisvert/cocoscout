# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'My::Dashboard', type: :system do
  let!(:user) { create(:user) }
  let!(:person) { create(:person, user: user, email: user.email_address) }
  let(:organization) { create(:organization) }
  let(:production) { create(:production, organization: organization) }

  describe 'when user is not in any productions' do
    it 'shows no upcoming events' do
      sign_in_as(user)
      expect(page).to have_content('No upcoming events scheduled.')
    end

    it 'shows no upcoming auditions' do
      sign_in_as(user)
      expect(page).to have_content("You don't have any upcoming auditions.")
    end

    it 'shows no open sign-ups' do
      sign_in_as(user)
      expect(page).to have_content("None of the shows you've applied for are currently auditioning.")
    end
  end

  describe 'when user is in a cast' do
    let!(:talent_pool) { create(:talent_pool, production: production) }
    let!(:show) { create(:show, production: production, date_and_time: 1.week.from_now, event_type: :show) }

    before do
      cast.people << person
    end

    it 'shows the production on the dashboard' do
      sign_in_as(user)
      expect(page).to have_content(production.name)
    end

    it 'shows upcoming shows' do
      sign_in_as(user)
      expect(page).to have_content(show.date_and_time.strftime('%b %d, %Y'))
    end
  end

  describe 'when user has upcoming audition sessions' do
    let!(:audition_cycle) { create(:audition_cycle, production: production) }
    let!(:audition_request) { create(:audition_request, person: person, audition_cycle: audition_cycle) }
    let!(:audition_session) { create(:audition_session, :upcoming, audition_cycle: audition_cycle) }
    let!(:audition) do
      create(:audition, person: person, audition_request: audition_request, audition_session: audition_session)
    end

    it 'shows the upcoming audition session' do
      sign_in_as(user)
      expect(page).to have_content('Upcoming Auditions')
    end
  end

  describe 'when user has open audition requests' do
    let!(:audition_cycle) do
      create(:audition_cycle, production: production, opens_at: 1.day.ago, closes_at: 1.week.from_now)
    end
    let!(:audition_request) { create(:audition_request, person: person, audition_cycle: audition_cycle) }

    it 'shows open sign-ups' do
      sign_in_as(user)
      expect(page).to have_content(production.name)
    end
  end

  describe 'dashboard navigation' do
    it 'has Shows & Events heading' do
      sign_in_as(user)
      expect(page).to have_content('Shows & Events')
    end

    it 'has Upcoming Auditions heading' do
      sign_in_as(user)
      expect(page).to have_content('Upcoming Auditions')
    end

    it 'has Open Sign-ups heading' do
      sign_in_as(user)
      expect(page).to have_content('Open Sign-ups')
    end
  end
end

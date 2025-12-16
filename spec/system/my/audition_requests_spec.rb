# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'My::AuditionRequests', type: :system do
  let!(:user) { create(:user) }
  let!(:person) { create(:person, user: user, email: user.email_address) }
  let(:organization) { create(:organization) }
  let(:production) { create(:production, organization: organization, name: 'The Phantom of the Opera') }

  describe 'when user has no audition requests' do
    it 'shows no sign-ups message' do
      sign_in_as_person(user, person)
      visit '/my/audition_requests?requests_filter=all'
      expect(page).to have_content("You haven't signed up for any auditions.")
    end
  end

  describe 'when user has audition requests' do
    let!(:audition_cycle) do
      create(:audition_cycle, production: production, opens_at: 1.day.ago, closes_at: 1.week.from_now, form_reviewed: true,
                              finalize_audition_invitations: true)
    end
    let!(:audition_request) do
      create(:audition_request, requestable: person, audition_cycle: audition_cycle)
    end

    it 'displays the audition request' do
      sign_in_as_person(user, person)
      visit '/my/audition_requests'

      expect(page).to have_content(production.name)
    end

    it 'shows request status as in review when not finalized' do
      audition_cycle.update(finalize_audition_invitations: false)
      sign_in_as_person(user, person)
      visit '/my/audition_requests'

      expect(page).to have_content('In Review')
    end

    it 'shows when auditions close' do
      sign_in_as_person(user, person)
      visit '/my/audition_requests'
      # Should see the production name
      expect(page).to have_content(production.name)
    end
  end

  describe 'audition request statuses based on scheduling' do
    let!(:audition_cycle) do
      create(:audition_cycle, production: production, opens_at: 1.day.ago, closes_at: 1.week.from_now, form_reviewed: true,
                              finalize_audition_invitations: true)
    end

    it 'shows no audition offered when not scheduled' do
      create(:audition_request, requestable: person, audition_cycle: audition_cycle)

      sign_in_as_person(user, person)
      visit '/my/audition_requests'
      expect(page).to have_content('No Audition Offered')
    end

    it 'shows audition offered when scheduled' do
      audition_request = create(:audition_request, requestable: person, audition_cycle: audition_cycle)
      audition_session = create(:audition_session, audition_cycle: audition_cycle)
      create(:audition, audition_session: audition_session, audition_request: audition_request, auditionable: person)

      sign_in_as_person(user, person)
      visit '/my/audition_requests'
      expect(page).to have_content('Audition Offered')
    end
  end

  describe 'multiple audition requests' do
    let!(:call2) do
      create(:audition_cycle, production: production, opens_at: 1.day.ago, closes_at: 1.week.from_now, form_reviewed: true,
                              finalize_audition_invitations: true)
    end
    let!(:request1) { create(:audition_request, requestable: person, audition_cycle: call2) }
    let!(:request2) { create(:audition_request, requestable: person, audition_cycle: call2) }

    it 'displays all audition requests' do
      sign_in_as_person(user, person)
      visit '/my/audition_requests'

      expect(page).to have_content(call2.closes_at.strftime('%b %d, %Y'))
    end
  end

  describe 'with answers to questions' do
    let!(:audition_cycle) { create(:audition_cycle, production: production, opens_at: 1.day.ago, closes_at: 1.week.from_now, form_reviewed: true) }
    let!(:question) { create(:question, questionable: audition_cycle, text: 'What is your favorite role?') }
    let!(:audition_request) { create(:audition_request, requestable: person, audition_cycle: audition_cycle) }
    let!(:answer) { create(:answer, audition_request: audition_request, question: question, value: 'Elphaba') }

    it 'allows viewing submitted answers' do
      sign_in_as_person(user, person)
      visit '/my/audition_requests'

      expect(page).to have_content(production.name)
    end
  end
end

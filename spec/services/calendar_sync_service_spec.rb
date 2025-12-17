# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CalendarSyncService, type: :service do
  describe '.find_eligible_people' do
    let(:production) { create(:production) }
    let(:talent_pool) { create(:talent_pool, production: production) }
    let(:show) { create(:show, production: production) }
    let(:person) { create(:person, calendar_sync_enabled: true, calendar_sync_email_confirmed: true) }

    before do
      # Add person to talent pool
      create(:talent_pool_membership, talent_pool: talent_pool, member: person)
    end

    context 'when person has calendar sync enabled' do
      it 'includes person in eligible list for all_shows scope' do
        person.update(
          calendar_sync_scope: 'all_shows',
          calendar_sync_entities: { 'person' => true }
        )

        eligible = CalendarSyncService.find_eligible_people(show)
        expect(eligible).to include(person)
      end

      it 'excludes person when person entity is disabled' do
        person.update(
          calendar_sync_scope: 'all_shows',
          calendar_sync_entities: { 'person' => false }
        )

        eligible = CalendarSyncService.find_eligible_people(show)
        expect(eligible).not_to include(person)
      end
    end

    context 'when person has calendar sync disabled' do
      it 'excludes person from eligible list' do
        person.update(calendar_sync_enabled: false)

        eligible = CalendarSyncService.find_eligible_people(show)
        expect(eligible).not_to include(person)
      end
    end

    context 'when person email is not confirmed' do
      it 'excludes person from eligible list' do
        person.update(calendar_sync_email_confirmed: false)

        eligible = CalendarSyncService.find_eligible_people(show)
        expect(eligible).not_to include(person)
      end
    end

    context 'with assignments_only scope' do
      let(:role) { create(:role, production: production) }

      before do
        person.update(
          calendar_sync_scope: 'assignments_only',
          calendar_sync_entities: { 'person' => true }
        )
      end

      it 'includes person when they have a role assignment' do
        create(:show_person_role_assignment, show: show, assignable: person, role: role)

        eligible = CalendarSyncService.find_eligible_people(show)
        expect(eligible).to include(person)
      end

      it 'excludes person when they have no role assignment' do
        eligible = CalendarSyncService.find_eligible_people(show)
        expect(eligible).not_to include(person)
      end
    end
  end
end

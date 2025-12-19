# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CalendarEvent, type: :model do
  describe 'associations' do
    it 'belongs to a calendar_subscription' do
      event = CalendarEvent.new
      expect(event).to respond_to(:calendar_subscription)
    end

    it 'belongs to a show' do
      event = CalendarEvent.new
      expect(event).to respond_to(:show)
    end
  end

  describe 'validations' do
    it 'is invalid without a provider_event_id' do
      event = CalendarEvent.new(provider_event_id: nil)
      expect(event).not_to be_valid
      expect(event.errors[:provider_event_id]).to include("can't be blank")
    end
  end

  describe '.generate_sync_hash' do
    it 'generates a hash based on show data' do
      production = create(:production)
      location = create(:location, organization: production.organization)
      show = create(:show, production: production, location: location)

      hash = described_class.generate_sync_hash(show)

      expect(hash).to be_present
      expect(hash.length).to eq(64) # SHA256 hex length
    end

    it 'generates consistent hashes for the same data' do
      production = create(:production)
      show = create(:show, production: production)

      hash1 = described_class.generate_sync_hash(show)
      hash2 = described_class.generate_sync_hash(show)

      expect(hash1).to eq(hash2)
    end

    it 'generates different hashes for different data' do
      production = create(:production)
      show1 = create(:show, production: production, secondary_name: 'First')
      show2 = create(:show, production: production, secondary_name: 'Second')

      hash1 = described_class.generate_sync_hash(show1)
      hash2 = described_class.generate_sync_hash(show2)

      expect(hash1).not_to eq(hash2)
    end
  end
end

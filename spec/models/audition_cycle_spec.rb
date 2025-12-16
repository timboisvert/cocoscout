# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuditionCycle, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      call = build(:audition_cycle)
      expect(call).to be_valid
    end

    it 'is invalid without opens_at' do
      call = build(:audition_cycle, opens_at: nil)
      expect(call).not_to be_valid
      expect(call.errors[:opens_at]).to include("can't be blank")
    end

    it 'is valid without closes_at (open-ended)' do
      call = build(:audition_cycle, closes_at: nil)
      expect(call).to be_valid
    end

    it 'validates closes_at is after opens_at when both are present' do
      call = build(:audition_cycle, opens_at: Time.current, closes_at: 1.day.ago)
      expect(call).not_to be_valid
      expect(call.errors[:closes_at]).to include('must be after the opening date and time')
    end
  end

  describe 'associations' do
    it 'belongs to production' do
      call = create(:audition_cycle)
      expect(call.production).to be_present
      expect(call).to respond_to(:production)
    end

    it 'has many audition_requests' do
      call = create(:audition_cycle)
      expect(call).to respond_to(:audition_requests)
    end

    it 'has many audition_sessions' do
      call = create(:audition_cycle)
      expect(call).to respond_to(:audition_sessions)
    end

    it 'has many questions' do
      call = create(:audition_cycle)
      expect(call).to respond_to(:questions)
    end
  end

  describe 'audition_type enum' do
    it 'can be in_person' do
      call = create(:audition_cycle, audition_type: :in_person)
      expect(call.audition_type).to eq('in_person')
      expect(call.in_person?).to be true
    end

    it 'can be video_upload' do
      call = create(:audition_cycle, :video_upload)
      expect(call.audition_type).to eq('video_upload')
      expect(call.video_upload?).to be true
    end
  end

  describe '#production_name' do
    it 'returns the name of the associated production' do
      production = create(:production, name: 'The Lion King')
      call = create(:audition_cycle, production: production)

      expect(call.production_name).to eq('The Lion King')
    end
  end

  describe '#counts' do
    let(:call) { create(:audition_cycle) }

    it 'returns counts for total, scheduled, and cast' do
      create(:audition_request, audition_cycle: call)
      create(:audition_request, audition_cycle: call)
      create(:audition_request, audition_cycle: call)

      counts = call.counts
      expect(counts[:total]).to eq(3)
      expect(counts[:scheduled]).to eq(0)
      expect(counts[:cast]).to eq(0)
    end

    it 'returns zero when no requests' do
      counts = call.counts
      expect(counts[:total]).to eq(0)
      expect(counts[:scheduled]).to eq(0)
      expect(counts[:cast]).to eq(0)
    end
  end

  describe '#timeline_status' do
    it 'returns :upcoming when opens_at is in the future' do
      call = create(:audition_cycle, :upcoming)
      expect(call.timeline_status).to eq(:upcoming)
    end

    it 'returns :open when current time is between opens_at and closes_at' do
      call = create(:audition_cycle, opens_at: 1.day.ago, closes_at: 1.day.from_now)
      expect(call.timeline_status).to eq(:open)
    end

    it 'returns :closed when closes_at is in the past' do
      call = create(:audition_cycle, :closed)
      expect(call.timeline_status).to eq(:closed)
    end

    it 'returns :open when closes_at is nil (open-ended) and opens_at is in the past' do
      call = create(:audition_cycle, :open_ended)
      expect(call.timeline_status).to eq(:open)
    end
  end

  describe '#respond_url' do
    let(:call) { create(:audition_cycle, token: 'abc123xyz') }

    it 'returns development URL in development environment' do
      allow(Rails.env).to receive(:development?).and_return(true)
      expect(call.respond_url).to eq('http://localhost:3000/a/abc123xyz')
    end

    it 'returns production URL in non-development environment' do
      allow(Rails.env).to receive(:development?).and_return(false)
      expect(call.respond_url).to eq('https://www.cocoscout.com/a/abc123xyz')
    end
  end

  describe 'rich text fields' do
    it 'has header_text as rich text' do
      call = create(:audition_cycle)
      call.update(header_text: '<p>Welcome to auditions!</p>')

      expect(call.header_text.to_s).to include('Welcome to auditions!')
    end

    it 'has video_field_text as rich text' do
      call = create(:audition_cycle)
      call.update(video_field_text: '<p>Upload your video here</p>')

      expect(call.video_field_text.to_s).to include('Upload your video here')
    end

    it 'has success_text as rich text' do
      call = create(:audition_cycle)
      call.update(success_text: '<p>Thank you for applying!</p>')

      expect(call.success_text.to_s).to include('Thank you for applying!')
    end
  end
end

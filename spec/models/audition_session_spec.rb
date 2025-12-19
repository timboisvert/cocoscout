# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuditionSession, type: :model do
  describe 'associations' do
    it 'belongs to an audition_cycle' do
      session = AuditionSession.new
      expect(session).to respond_to(:audition_cycle)
    end

    it 'has one production through audition_cycle' do
      session = AuditionSession.new
      expect(session).to respond_to(:production)
    end

    it 'has many auditions' do
      session = AuditionSession.new
      expect(session).to respond_to(:auditions)
    end

    it 'has many audition_session_availabilities' do
      session = AuditionSession.new
      expect(session).to respond_to(:audition_session_availabilities)
    end

    it 'belongs to a location' do
      session = AuditionSession.new
      expect(session).to respond_to(:location)
    end
  end

  describe 'validations' do
    it 'is invalid without a start_at' do
      session = AuditionSession.new(start_at: nil)
      expect(session).not_to be_valid
      expect(session.errors[:start_at]).to include("can't be blank")
    end

    it 'is invalid without an audition_cycle' do
      session = AuditionSession.new(audition_cycle: nil)
      expect(session).not_to be_valid
      expect(session.errors[:audition_cycle]).to include("can't be blank")
    end

    it 'is invalid without a location' do
      session = AuditionSession.new(location: nil)
      expect(session).not_to be_valid
      expect(session.errors[:location]).to include("can't be blank")
    end
  end
end

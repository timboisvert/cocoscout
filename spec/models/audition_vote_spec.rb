# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuditionVote, type: :model do
  describe 'associations' do
    it 'belongs to an audition' do
      vote = AuditionVote.new
      expect(vote).to respond_to(:audition)
    end

    it 'belongs to a user' do
      vote = AuditionVote.new
      expect(vote).to respond_to(:user)
    end
  end

  describe 'validations' do
    it 'is invalid without a vote' do
      vote = AuditionVote.new(vote: nil)
      expect(vote).not_to be_valid
      expect(vote.errors[:vote]).to include("can't be blank")
    end
  end

  describe 'enums' do
    it 'defines vote types' do
      expect(described_class.votes).to eq({
        'yes' => 0,
        'no' => 1,
        'maybe' => 2
      })
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe AuditionRequestVote, type: :model do
  describe "associations" do
    it "belongs to audition_request" do
      audition_request = create(:audition_request)
      user = create(:user)
      vote = described_class.create!(audition_request: audition_request, user: user, vote: :yes)
      expect(vote.audition_request).to eq(audition_request)
    end

    it "belongs to user" do
      audition_request = create(:audition_request)
      user = create(:user)
      vote = described_class.create!(audition_request: audition_request, user: user, vote: :yes)
      expect(vote.user).to eq(user)
    end
  end

  describe "validations" do
    it "requires a vote" do
      audition_request = create(:audition_request)
      user = create(:user)
      vote = described_class.new(audition_request: audition_request, user: user, vote: nil)
      expect(vote).not_to be_valid
    end

    describe "uniqueness of user per audition_request" do
      let(:audition_request) { create(:audition_request) }
      let(:user) { create(:user) }

      before do
        described_class.create!(
          audition_request: audition_request,
          user: user,
          vote: :yes
        )
      end

      it "prevents duplicate votes from same user" do
        duplicate = described_class.new(
          audition_request: audition_request,
          user: user,
          vote: :no
        )

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:user_id]).to include("has already voted on this sign-up")
      end

      it "allows same user to vote on different requests" do
        other_request = create(:audition_request)

        vote = described_class.new(
          audition_request: other_request,
          user: user,
          vote: :yes
        )

        expect(vote).to be_valid
      end
    end
  end

  describe "enums" do
    it "defines vote enum with yes, no, maybe" do
      expect(described_class.votes).to eq({
        "yes" => 0,
        "no" => 1,
        "maybe" => 2
      })
    end
  end

  describe "vote values" do
    let(:audition_request) { create(:audition_request) }
    let(:user) { create(:user) }

    it "accepts yes vote" do
      vote = described_class.new(audition_request: audition_request, user: user, vote: :yes)
      expect(vote).to be_valid
      expect(vote.yes?).to be true
    end

    it "accepts no vote" do
      vote = described_class.new(audition_request: audition_request, user: user, vote: :no)
      expect(vote).to be_valid
      expect(vote.no?).to be true
    end

    it "accepts maybe vote" do
      vote = described_class.new(audition_request: audition_request, user: user, vote: :maybe)
      expect(vote).to be_valid
      expect(vote.maybe?).to be true
    end
  end
end

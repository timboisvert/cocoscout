# frozen_string_literal: true

require "rails_helper"

RSpec.describe AuditionReviewer, type: :model do
  describe "associations" do
    it "belongs to audition_cycle" do
      audition_cycle = create(:audition_cycle)
      person = create(:person)
      reviewer = described_class.create!(audition_cycle: audition_cycle, person: person)
      expect(reviewer.audition_cycle).to eq(audition_cycle)
    end

    it "belongs to person" do
      audition_cycle = create(:audition_cycle)
      person = create(:person)
      reviewer = described_class.create!(audition_cycle: audition_cycle, person: person)
      expect(reviewer.person).to eq(person)
    end
  end

  describe "validations" do
    describe "uniqueness of person per audition_cycle" do
      let(:audition_cycle) { create(:audition_cycle) }
      let(:person) { create(:person) }

      before do
        described_class.create!(
          audition_cycle: audition_cycle,
          person: person
        )
      end

      it "prevents duplicate person per cycle" do
        duplicate = described_class.new(
          audition_cycle: audition_cycle,
          person: person
        )

        expect(duplicate).not_to be_valid
      end

      it "allows same person in different cycles" do
        other_cycle = create(:audition_cycle)
        reviewer = described_class.new(
          audition_cycle: other_cycle,
          person: person
        )

        expect(reviewer).to be_valid
      end
    end
  end
end

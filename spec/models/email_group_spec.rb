# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmailGroup, type: :model do
  describe "associations" do
    it "belongs to audition_cycle" do
      audition_cycle = create(:audition_cycle)
      email_group = described_class.create!(
        audition_cycle: audition_cycle,
        group_id: "1",
        name: "Group A"
      )
      expect(email_group.audition_cycle).to eq(audition_cycle)
    end
  end

  describe "validations" do
    let(:audition_cycle) { create(:audition_cycle) }

    it "requires group_id" do
      email_group = described_class.new(audition_cycle: audition_cycle, group_id: nil, name: "Test")
      expect(email_group).not_to be_valid
    end

    it "requires name" do
      email_group = described_class.new(audition_cycle: audition_cycle, group_id: "1", name: nil)
      expect(email_group).not_to be_valid
    end

    it "validates name max length of 30" do
      email_group = described_class.new(audition_cycle: audition_cycle, group_id: "1", name: "a" * 31)
      expect(email_group).not_to be_valid
    end

    describe "uniqueness of group_id scoped to audition_cycle" do
      before do
        described_class.create!(
          audition_cycle: audition_cycle,
          group_id: "1",
          name: "Group A"
        )
      end

      it "prevents duplicate group_id per cycle" do
        duplicate = described_class.new(
          audition_cycle: audition_cycle,
          group_id: "1",
          name: "Group B"
        )

        expect(duplicate).not_to be_valid
      end

      it "allows same group_id in different cycles" do
        other_cycle = create(:audition_cycle)
        email_group = described_class.new(
          audition_cycle: other_cycle,
          group_id: "1",
          name: "Group C"
        )

        expect(email_group).to be_valid
      end
    end
  end
end

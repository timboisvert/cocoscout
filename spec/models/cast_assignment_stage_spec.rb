# frozen_string_literal: true

require "rails_helper"

RSpec.describe CastAssignmentStage, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:audition_cycle) }
    it { is_expected.to belong_to(:talent_pool) }
    it { is_expected.to belong_to(:assignable) }
    it { is_expected.to have_one(:production).through(:audition_cycle) }
  end

  describe "validations" do
    let(:audition_cycle) { create(:audition_cycle) }
    let(:talent_pool) { create(:talent_pool, production: audition_cycle.production) }
    let(:role) { create(:role, show: create(:show, production: audition_cycle.production)) }

    it "requires audition_cycle_id" do
      stage = build(:cast_assignment_stage, audition_cycle: nil, talent_pool: talent_pool, assignable: role)
      expect(stage).not_to be_valid
    end

    it "requires talent_pool_id" do
      stage = build(:cast_assignment_stage, audition_cycle: audition_cycle, talent_pool: nil, assignable: role)
      expect(stage).not_to be_valid
    end

    it "requires assignable" do
      stage = build(:cast_assignment_stage, audition_cycle: audition_cycle, talent_pool: talent_pool, assignable: nil)
      expect(stage).not_to be_valid
    end

    it "enforces uniqueness of assignable per audition_cycle and talent_pool" do
      create(:cast_assignment_stage,
        audition_cycle: audition_cycle,
        talent_pool: talent_pool,
        assignable: role
      )

      duplicate = build(:cast_assignment_stage,
        audition_cycle: audition_cycle,
        talent_pool: talent_pool,
        assignable: role
      )

      expect(duplicate).not_to be_valid
    end
  end

  describe "status enum" do
    it "defaults to pending" do
      audition_cycle = create(:audition_cycle)
      talent_pool = create(:talent_pool, production: audition_cycle.production)
      role = create(:role, show: create(:show, production: audition_cycle.production))

      stage = CastAssignmentStage.create!(
        audition_cycle: audition_cycle,
        talent_pool: talent_pool,
        assignable: role
      )

      expect(stage.status).to eq("pending")
    end

    it "can be set to finalized" do
      audition_cycle = create(:audition_cycle)
      talent_pool = create(:talent_pool, production: audition_cycle.production)
      role = create(:role, show: create(:show, production: audition_cycle.production))

      stage = CastAssignmentStage.create!(
        audition_cycle: audition_cycle,
        talent_pool: talent_pool,
        assignable: role,
        status: :finalized
      )

      expect(stage.status).to eq("finalized")
    end
  end
end

FactoryBot.define do
  factory :cast_assignment_stage do
    association :audition_cycle
    association :talent_pool
    association :assignable, factory: :role
    status { :pending }
  end
end unless FactoryBot.factories.registered?(:cast_assignment_stage)

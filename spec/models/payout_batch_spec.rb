# frozen_string_literal: true

require "rails_helper"

RSpec.describe PayoutBatch do
  describe "#timeline_steps" do
    def states(batch)
      batch.timeline_steps.map { |s| s[:state] }
    end

    it "labels the steps in lifecycle order" do
      batch = build(:payout_batch, status: "draft")
      expect(batch.timeline_steps.map { |s| s[:label] }).to eq(%w[Created Funding Funded Paying Paid])
    end

    it "marks the current step for a draft run" do
      expect(states(build(:payout_batch, status: "draft"))).to eq(%i[current upcoming upcoming upcoming upcoming])
    end

    it "advances the current step while funding" do
      expect(states(build(:payout_batch, status: "funding"))).to eq(%i[done current upcoming upcoming upcoming])
    end

    it "marks every step done when completed" do
      expect(states(build(:payout_batch, status: "completed"))).to all(eq(:done))
    end

    it "flags the Funding step red when funding failed" do
      batch = build(:payout_batch, status: "failed", funding_status: "failed")
      expect(states(batch)).to eq(%i[done failed upcoming upcoming upcoming])
    end

    it "flags the Paying step red when a transfer failed after funding" do
      batch = build(:payout_batch, status: "failed", funding_status: "succeeded")
      expect(states(batch)).to eq(%i[done done done failed upcoming])
    end
  end
end

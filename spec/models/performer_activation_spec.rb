# frozen_string_literal: true

require "rails_helper"

RSpec.describe PerformerActivation do
  let(:org) { create(:organization, :pro) }
  let(:person) { create(:person) }

  describe ".record!" do
    it "is idempotent per organization / person / month" do
      first = nil
      expect {
        first = described_class.record!(organization: org, person: person, month: Date.current)
      }.to change(described_class, :count).by(1)

      expect {
        again = described_class.record!(organization: org, person: person, month: Date.current)
        expect(again).to eq(first)
      }.not_to change(described_class, :count)
    end

    it "normalizes the month to the first of the month and stamps first_activated_at" do
      rec = described_class.record!(organization: org, person: person, month: Date.new(2026, 7, 17))
      expect(rec.billing_month).to eq(Date.new(2026, 7, 1))
      expect(rec.first_activated_at).to be_present
    end

    it "enqueues a meter report on insert only" do
      expect {
        described_class.record!(organization: org, person: person, month: Date.current)
      }.to have_enqueued_job(MeterPerformerActivationJob)

      expect {
        described_class.record!(organization: org, person: person, month: Date.current)
      }.not_to have_enqueued_job(MeterPerformerActivationJob)
    end
  end
end

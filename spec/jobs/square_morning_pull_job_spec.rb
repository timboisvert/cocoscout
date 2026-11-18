# frozen_string_literal: true

require "rails_helper"

RSpec.describe SquareMorningPullJob, type: :job do
  let(:owner) { create(:user) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:integration) { org.integrations.create!(provider: "square", tokens: { "access_token" => "tok", "merchant_id" => "M1" }) }

  # Tim, 2026-11-16: the 5 am pull read the night before last, because a
  # business day runs to 6 am, so Sunday's bar never reached Settle up on Monday.
  it "reads last night at 5 am, before the business day rolls over" do
    org.update!(settlement_day_mode: "smart", settlement_day_starts_at: 6)
    travel_to(Time.zone.local(2026, 11, 16, 5, 0)) do
      expect { described_class.perform_now }
        .to have_enqueued_job(SquarePullJob).with(integration.id, from: Date.new(2026, 11, 14), to: Date.new(2026, 11, 15), trigger: "morning")
    end
  end

  it "reads last night when the day has already rolled over" do
    org.update!(settlement_day_mode: "calendar")
    travel_to(Time.zone.local(2026, 11, 16, 5, 0)) do
      expect { described_class.perform_now }
        .to have_enqueued_job(SquarePullJob).with(integration.id, from: Date.new(2026, 11, 15), to: Date.new(2026, 11, 16), trigger: "morning")
    end
  end
end

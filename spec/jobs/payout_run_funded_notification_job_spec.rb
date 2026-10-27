# frozen_string_literal: true

require "rails_helper"

RSpec.describe PayoutRunFundedNotificationJob, type: :job do
  include ActiveJob::TestHelper

  let(:owner) { create(:user) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_person) { create(:person, user: owner, email: "owner@sg.example") }
  let(:batch) do
    org.payout_batches.create!(kind: "staff_pay", status: "processing", trigger: "manual", funding_status: "succeeded",
                               total_cents: 12_500, payday: Date.current, funded_at: Time.current)
  end

  before do
    batch.items.create!(payee: create(:person), amount_cents: 12_500, status: "pending")
    org.update!(payout_notification_user_ids: [ owner.id ])
    ActionMailer::Base.deliveries.clear
  end

  it "tells the chosen people the run is funded and payments are going out" do
    expect { perform_enqueued_jobs { described_class.perform_now(batch.id) } }
      .to change(Notification, :count).by(1).and change { ActionMailer::Base.deliveries.size }.by(1)

    notification = owner.notifications.last
    expect(notification.category).to eq("pay")
    expect(notification.kind).to eq("payout_run_funded")
    expect(notification.title).to eq("Your $125.00 payout run is funded — payments are going out")
    expect(notification.path).to eq("/manage/money/payout-runs/#{batch.id}")
    expect(ActionMailer::Base.deliveries.last.to).to eq([ "owner@sg.example" ])
  end

  it "does nothing for a run that isn't funded" do
    batch.update!(funded_at: nil)
    expect { perform_enqueued_jobs { described_class.perform_now(batch.id) } }.not_to change(Notification, :count)
  end
end

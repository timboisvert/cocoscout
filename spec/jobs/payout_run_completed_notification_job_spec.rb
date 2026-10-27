# frozen_string_literal: true

require "rails_helper"

RSpec.describe PayoutRunCompletedNotificationJob, type: :job do
  include ActiveJob::TestHelper

  let(:owner) { create(:user) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_person) { create(:person, user: owner, email: "owner@sg.example") }
  let(:batch) do
    org.payout_batches.create!(kind: "payout", status: "partially_paid", trigger: "manual", funding_status: "succeeded",
                               total_cents: 9_000, payday: Date.new(2026, 10, 27), funded_at: Time.current)
  end

  before do
    batch.items.create!(payee: create(:person, name: "Ready Rita"), amount_cents: 4_000, status: "paid", paid_at: Time.current)
    batch.items.create!(payee: create(:person, name: "Paid Pat"), amount_cents: 2_000, status: "paid", paid_at: Time.current)
    batch.items.create!(payee: create(:person, name: "Nobank Ned"), amount_cents: 3_000, status: "pending")
    org.update!(payout_notification_user_ids: [ owner.id ])
    ActionMailer::Base.deliveries.clear
  end

  it "names who's still waiting when the run is partly paid" do
    expect { perform_enqueued_jobs { described_class.perform_now(batch.id, "partially_paid") } }
      .to change(Notification, :count).by(1).and change { ActionMailer::Base.deliveries.size }.by(1)

    notification = owner.notifications.last
    expect(notification.kind).to eq("payout_run_partly_paid")
    expect(notification.title).to eq("2 people paid, 1 waiting on bank details")
    html = ActionMailer::Base.deliveries.last.html_part.body.decoded
    expect(html).to include("$60.00").and include("Nobank Ned").and include("$30.00")
    expect(html).not_to include("Ready Rita")
  end

  it "counts everyone and the money when the run is completed" do
    batch.items.where(status: "pending").update_all(status: "paid", paid_at: Time.current)
    batch.update!(status: "completed", completed_at: Time.current)

    perform_enqueued_jobs { described_class.perform_now(batch.id, "completed") }

    notification = owner.notifications.last
    expect(notification.kind).to eq("payout_run_completed")
    expect(notification.title).to eq("Everyone's paid: 3 people, $90.00")
    expect(notification.path).to eq("/manage/money/payout-runs/#{batch.id}")
    expect(ActionMailer::Base.deliveries.last.html_part.body.decoded).to include("October 27")
  end

  it "sends nothing for any other status" do
    expect { perform_enqueued_jobs { described_class.perform_now(batch.id, "processing") } }.not_to change(Notification, :count)
  end
end

# frozen_string_literal: true

require "rails_helper"

# The bounced-debit notice used to create the Notification and then log "No
# mailer specified": the email never went.
RSpec.describe PayoutFundingFailedNotificationJob, type: :job do
  include ActiveJob::TestHelper

  let(:owner) { create(:user) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_person) { create(:person, user: owner, email: "owner@sg.example") }
  let(:batch) do
    org.payout_batches.create!(kind: "staff_pay", status: "failed", trigger: "manual", funding_status: "failed",
                               total_cents: 1_000, funding_error: "Insufficient funds.")
  end

  before do
    batch.items.create!(payee: create(:person), amount_cents: 1_000, status: "pending")
    org.update!(payout_notification_user_ids: [ owner.id ])
    ActionMailer::Base.deliveries.clear
  end

  it "records the Notification and really delivers the email, from no one" do
    expect { perform_enqueued_jobs { described_class.perform_now(batch.id) } }
      .to change(Notification, :count).by(1).and change { ActionMailer::Base.deliveries.size }.by(1).and(not_change(Message, :count))

    notification = owner.notifications.last
    expect(notification.category).to eq("pay")
    expect(notification.kind).to eq("payout_funding_failed")
    expect(notification.path).to eq("/manage/money/payout-runs/#{batch.id}")

    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([ "owner@sg.example" ])
    expect(mail.subject).to eq("The debit for your $10.00 payout run didn't go through")
    expect(mail.html_part.body.decoded).to include("payout-runs/#{batch.id}")
  end

  it "does nothing for a run whose funding didn't fail" do
    batch.update!(status: "funding", funding_status: "processing")
    expect { perform_enqueued_jobs { described_class.perform_now(batch.id) } }.not_to change(Notification, :count)
  end
end

# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261027100100_add_payout_run_lifecycle_templates")

# The submitted notice to the organization's chosen people: a Notification
# for each, an email that really goes, never from a person.
RSpec.describe PayoutRunSubmittedNotificationJob, type: :job do
  include ActiveJob::TestHelper

  let(:owner) { create(:user, email_address: "owner@sg.example") }
  let!(:org) { create(:organization, name: "Stars and Garters", owner: owner) }
  let!(:owner_person) { create(:person, name: "Olive Owner", user: owner, email: "owner@sg.example") }
  let(:payee) { create(:person, name: "Ready Rita", stripe_account_id: "acct_r", payouts_enabled: true) }
  let(:batch) do
    org.payout_batches.create!(kind: "staff_pay", status: "funding", trigger: "manual", funding_status: "processing",
                               funding_payment_intent_id: "pi_1", total_cents: 4_000, payday: Date.current)
  end

  before do
    batch.items.create!(payee: payee, amount_cents: 4_000, status: "pending")
    org.update!(payout_notification_user_ids: [ owner.id ])
    ActionMailer::Base.deliveries.clear
  end

  it "records a Notification in Pay with the run's page, and emails names, amounts, the window and a link" do
    expect { perform_enqueued_jobs { described_class.perform_now(batch.id) } }
      .to change(Notification, :count).by(1).and change { ActionMailer::Base.deliveries.size }.by(1).and(not_change(Message, :count))

    notification = owner.notifications.last
    expect(notification.category).to eq("pay")
    expect(notification.kind).to eq("payout_run_submitted")
    expect(notification.path).to eq("/manage/money/payout-runs/#{batch.id}")
    expect(notification.title).to eq("Payout run submitted — $40.00 to 1 payee")
    expect(notification.message).to be_nil

    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([ "owner@sg.example" ])
    expect(mail.subject).to eq("Payout run submitted — $40.00 to 1 payee")
    html = mail.html_part.body.decoded
    expect(html).to include("Hi Olive").and include("Ready Rita").and include("$40.00")
    expect(html).to include("payout-runs/#{batch.id}")
    expect(html).not_to include("Stripe")
  end

  it "says submitted and funded when the money settled in the same request" do
    perform_enqueued_jobs { described_class.perform_now(batch.id, funded: true) }
    expect(owner.notifications.last.title).to eq("Payout run submitted and funded — $40.00 to 1 payee")
    expect(ActionMailer::Base.deliveries.last.subject).to include("submitted and funded")
  end

  it "uses the deployed copy: 'payments are going out now' only when funded" do
    # The spec seed isn't the rake task's wording, so the migration would keep it as hand-edited.
    ContentTemplate.where(key: "payout_run_submitted").delete_all
    ActiveRecord::Migration.suppress_messages { AddPayoutRunLifecycleTemplates.new.up }

    perform_enqueued_jobs { described_class.perform_now(batch.id, funded: true) }
    expect(ActionMailer::Base.deliveries.last.html_part.body.decoded).to include("Payments are going out now")

    perform_enqueued_jobs { described_class.perform_now(batch.id, funded: false) }
    html = ActionMailer::Base.deliveries.last.html_part.body.decoded
    expect(html).to include("once the money comes in from your bank")
    expect(html).not_to include("going out now")
  end

  it "sends nothing when no one is chosen, or the run never started funding" do
    org.update!(payout_notification_user_ids: [])
    expect { perform_enqueued_jobs { described_class.perform_now(batch.id) } }.not_to change(Notification, :count)

    org.update!(payout_notification_user_ids: [ owner.id ])
    batch.update!(status: "failed", funding_status: "failed")
    expect { perform_enqueued_jobs { described_class.perform_now(batch.id) } }.not_to change(Notification, :count)
    expect(ActionMailer::Base.deliveries).to be_empty
  end
end

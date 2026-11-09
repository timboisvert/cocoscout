# frozen_string_literal: true

require "rails_helper"

# The one email telling everyone CocoScout has an app (Tim, 2026-11-09):
# once each, a batch at a time, to people who could use it and don't have it.
RSpec.describe AppAnnouncement do
  include ActiveJob::TestHelper

  def user(seen: 2.days.ago, **attrs) = create(:user, last_seen_at: seen, **attrs)

  let!(:ada) { user(seen: 1.day.ago).tap { |u| create(:person, user: u, name: "Ada Lovelace") } }
  let!(:ben) { user(seen: 40.days.ago) }
  let!(:old) { user(seen: 200.days.ago) }

  it "reaches people with an account who have used it, and nobody it shouldn't" do
    has_app = user.tap { |u| AppActivityDay.create!(user: u, day: Date.current, platform: "ios") }
    leaving = user(deletion_requested_at: 1.day.ago)
    bounced = user.tap { |u| EmailSuppression.suppress!(u.email_address.upcase, reason: "bounced") }
    never_came_in = user(seen: nil)
    told = user(app_announced_at: 1.week.ago)

    expect(described_class.audience).to eq([ ada, ben, old ])
    expect(described_class.audience).not_to include(has_app, leaving, bounced, never_came_in, told)
    expect(described_class.audience(seen_since: 90.days.ago)).to eq([ ada, ben ])
    expect(described_class.announce!(dry_run: true)).to eq(3)
    expect(ada.reload.app_announced_at).to be_nil
  end

  it "sends a batch, the most recently seen first, and never the same person twice" do
    expect { expect(described_class.announce!(limit: 2)).to eq(2) }.to have_enqueued_job(ActionMailer::MailDeliveryJob).twice
    expect([ ada, ben, old ].map { |u| u.reload.app_announced_at.present? }).to eq([ true, true, false ])

    expect { expect(described_class.announce!(limit: 50)).to eq(1) }.to have_enqueued_job(ActionMailer::MailDeliveryJob).once
    expect { expect(described_class.announce!(limit: 50)).to eq(0) }.not_to have_enqueued_job(ActionMailer::MailDeliveryJob)
  end

  it "sends one copy to look at without marking anyone as told" do
    expect { described_class.send_test!(ada.email_address) }.to have_enqueued_job(ActionMailer::MailDeliveryJob).once
    expect { described_class.send_test!("someone.else@example.com") }.to have_enqueued_job(ActionMailer::MailDeliveryJob).once
    expect(ada.reload.app_announced_at).to be_nil
    expect(described_class.announce!(dry_run: true)).to eq(3)
  end

  it "says what the app is, with the store links, and leaves the footer's own line about the app off" do
    perform_enqueued_jobs { described_class.announce!(limit: 1) }
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([ ada.email_address ])
    expect(mail.subject).to eq("New: the CocoScout app for iPhone and Android")
    body = mail.html_part ? mail.html_part.body.to_s : mail.body.to_s
    expect(body).to include("Hi Ada,", "The CocoScout app just launched", "you sign in with the account you already have", "/app", AppStores::APP_STORE_URL, AppStores::PLAY_STORE_URL,
                            "one-time note")
    expect(body).not_to include("with a buzz when something changes")
    # Every other email keeps that line.
    AppMailer.with(template_key: "cocoscout_bill_paid", to: "x@example.com", variables: {}).send_template.deliver_now
    other = ActionMailer::Base.deliveries.last
    expect((other.html_part ? other.html_part.body : other.body).to_s).to include("with a buzz when something changes")
  end
end

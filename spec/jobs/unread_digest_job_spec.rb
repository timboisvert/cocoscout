# frozen_string_literal: true

require "rails_helper"

RSpec.describe UnreadDigestJob do
  let(:user) { create(:user, message_digest_enabled: true) }
  let(:message) { create(:message, created_at: 5.hours.ago) }

  before { create(:message_subscription, user: user, message: message, unread_count: 1) }

  it "emails about messages still unread four hours later, not before" do
    message.update_columns(created_at: 3.hours.ago)
    described_class.perform_now
    expect(user.reload.last_unread_digest_sent_at).to be_nil

    message.update_columns(created_at: 5.hours.ago)
    described_class.perform_now
    expect(user.reload.last_unread_digest_sent_at).to be_present
  end

  # Push already told them; the email only catches what's still unread two
  # days later (Tim, 2026-10-12; two days from 2026-10-28).
  it "waits two days for someone whose phone gets push notifications" do
    create(:device_token, user: user)
    message.update_columns(created_at: 25.hours.ago)
    described_class.perform_now
    expect(user.reload.last_unread_digest_sent_at).to be_nil

    message.update_columns(created_at: 49.hours.ago)
    described_class.perform_now
    expect(user.reload.last_unread_digest_sent_at).to be_present
  end

  # Tim, 2026-11-09: fewer emails. A third of a month's digests went to
  # people who hadn't been on the site in thirty days.
  describe "someone who never comes back" do
    include ActiveJob::TestHelper

    # The job's query reads the database's clock, so the last digest is moved
    # back instead of the clock forward.
    def run(sent, last_digest_days_ago: nil)
      user.update_columns(last_unread_digest_sent_at: last_digest_days_ago.days.ago) if last_digest_days_ago
      expect { described_class.perform_now }.to change { enqueued_jobs.count { |j| j["job_class"] == "ActionMailer::MailDeliveryJob" } }.by(sent)
    end

    it "gets three digests, then none until they come back, then they start again" do
      run(1)
      run(1, last_digest_days_ago: 2)
      run(1, last_digest_days_ago: 3)
      expect(user.reload.digests_ignored).to eq(2)
      # The third ignored in a row: nothing goes, now or weeks on.
      run(0, last_digest_days_ago: 5)
      expect(user.reload.digests_ignored).to eq(3)
      run(0, last_digest_days_ago: 30)
      run(0, last_digest_days_ago: 60)
      expect(user.reload.digests_ignored).to eq(3)

      # They come back, leave it unread, and the digest starts over.
      user.update_columns(last_seen_at: 1.day.ago)
      run(1)
      expect(user.reload).to have_attributes(digests_ignored: 0, digest_throttle_days: 1)
    end

    it "keeps going for someone who opens the site between digests" do
      run(1)
      4.times do
        user.update_columns(last_seen_at: 1.day.ago)
        run(1, last_digest_days_ago: 2)
      end
      expect(user.reload.digests_ignored).to eq(0)
    end
  end
end

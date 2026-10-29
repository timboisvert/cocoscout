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
end

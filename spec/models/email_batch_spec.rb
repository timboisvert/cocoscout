# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmailBatch, type: :model do
  let(:user) { create(:user) }

  describe "associations" do
    it "belongs to user" do
      batch = create(:email_batch, user: user, subject: "Test")
      expect(batch.user).to eq(user)
    end

    it "has many email_logs" do
      batch = create(:email_batch, user: user, subject: "Test")
      expect(batch).to respond_to(:email_logs)
    end
  end

  describe "validations" do
    it "requires subject" do
      batch = build(:email_batch, user: user, subject: nil)
      expect(batch).not_to be_valid
      expect(batch.errors[:subject]).to be_present
    end

    it "is valid with subject" do
      batch = build(:email_batch, user: user, subject: "Test Subject")
      expect(batch).to be_valid
    end
  end

  describe ".recent" do
    it "orders by sent_at descending" do
      batch1 = create(:email_batch, user: user, subject: "First", sent_at: 2.days.ago)
      batch2 = create(:email_batch, user: user, subject: "Second", sent_at: 1.day.ago)
      batch3 = create(:email_batch, user: user, subject: "Third", sent_at: Time.current)

      expect(EmailBatch.recent.pluck(:id)).to eq([ batch3.id, batch2.id, batch1.id ])
    end
  end

  describe "#update_recipient_count!" do
    it "updates recipient_count based on email_logs" do
      batch = create(:email_batch, user: user, subject: "Test", recipient_count: 0)
      create(:email_log, email_batch: batch, user: user, recipient: "a@test.com")
      create(:email_log, email_batch: batch, user: user, recipient: "b@test.com")

      batch.update_recipient_count!

      expect(batch.recipient_count).to eq(2)
    end
  end
end

FactoryBot.define do
  factory :email_batch do
    association :user
    subject { "Test Email Subject" }
    sent_at { Time.current }
    recipient_count { 0 }
  end
end unless FactoryBot.factories.registered?(:email_batch)

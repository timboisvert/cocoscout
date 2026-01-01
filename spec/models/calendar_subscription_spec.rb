# frozen_string_literal: true

require "rails_helper"

RSpec.describe CalendarSubscription, type: :model do
  describe "associations" do
    it "belongs to person" do
      person = create(:person)
      subscription = described_class.create!(
        person: person,
        provider: "ical",
        sync_scope: "assigned"
      )
      expect(subscription.person).to eq(person)
    end

    it "has many calendar_events" do
      person = create(:person)
      subscription = described_class.create!(
        person: person,
        provider: "ical",
        sync_scope: "assigned"
      )
      expect(subscription).to respond_to(:calendar_events)
    end
  end

  describe "validations" do
    it "requires provider" do
      person = create(:person)
      subscription = described_class.new(person: person, provider: nil, sync_scope: "assigned")
      expect(subscription).not_to be_valid
    end

    it "requires sync_scope" do
      person = create(:person)
      subscription = described_class.new(person: person, provider: "ical", sync_scope: nil)
      expect(subscription).not_to be_valid
    end

    it "validates provider inclusion" do
      person = create(:person)
      subscription = described_class.new(person: person, provider: "invalid", sync_scope: "assigned")
      expect(subscription).not_to be_valid
    end

    it "validates sync_scope inclusion" do
      person = create(:person)
      subscription = described_class.new(person: person, provider: "ical", sync_scope: "invalid")
      expect(subscription).not_to be_valid
    end

    describe "uniqueness of person_id scoped to provider" do
      let(:person) { create(:person) }

      before do
        described_class.create!(
          person: person,
          provider: "google",
          sync_scope: "assigned"
        )
      end

      it "prevents duplicate subscriptions for same provider" do
        duplicate = described_class.new(
          person: person,
          provider: "google",
          sync_scope: "talent_pool"
        )

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:person_id]).to include("already has a subscription for this provider")
      end

      it "allows different providers for same person" do
        ical_sub = described_class.new(
          person: person,
          provider: "ical",
          sync_scope: "assigned"
        )

        expect(ical_sub).to be_valid
      end
    end
  end

  describe "callbacks" do
    describe "before_create :generate_ical_token" do
      it "generates token for ical provider" do
        person = create(:person)
        subscription = described_class.create!(
          person: person,
          provider: "ical",
          sync_scope: "assigned"
        )

        expect(subscription.ical_token).to be_present
      end

      it "does not generate token for google provider" do
        person = create(:person)
        subscription = described_class.create!(
          person: person,
          provider: "google",
          sync_scope: "assigned"
        )

        expect(subscription.ical_token).to be_nil
      end
    end
  end

  describe "#token_valid?" do
    let(:person) { create(:person) }

    context "for ical provider" do
      it "always returns true" do
        subscription = described_class.new(person: person, provider: "ical", sync_scope: "assigned")
        expect(subscription.token_valid?).to be true
      end
    end

    context "for google provider" do
      it "returns false when access_token is blank" do
        subscription = described_class.new(
          person: person,
          provider: "google",
          sync_scope: "assigned",
          access_token: nil
        )
        expect(subscription.token_valid?).to be false
      end

      it "returns true when token_expires_at is nil" do
        subscription = described_class.new(
          person: person,
          provider: "google",
          sync_scope: "assigned",
          access_token: "token123",
          token_expires_at: nil
        )
        expect(subscription.token_valid?).to be true
      end

      it "returns true when token not expired" do
        subscription = described_class.new(
          person: person,
          provider: "google",
          sync_scope: "assigned",
          access_token: "token123",
          token_expires_at: 1.hour.from_now
        )
        expect(subscription.token_valid?).to be true
      end

      it "returns false when token expired" do
        subscription = described_class.new(
          person: person,
          provider: "google",
          sync_scope: "assigned",
          access_token: "token123",
          token_expires_at: 1.hour.ago
        )
        expect(subscription.token_valid?).to be false
      end
    end
  end

  describe "#token_expired?" do
    let(:person) { create(:person) }

    it "returns opposite of token_valid?" do
      subscription = described_class.new(person: person, provider: "ical", sync_scope: "assigned")
      expect(subscription.token_expired?).to eq(!subscription.token_valid?)
    end
  end

  describe "#needs_reauthorization?" do
    let(:person) { create(:person) }

    context "for ical provider" do
      it "returns false" do
        subscription = described_class.new(person: person, provider: "ical", sync_scope: "assigned")
        expect(subscription.needs_reauthorization?).to be false
      end
    end

    context "for google provider" do
      it "returns true when access_token is blank" do
        subscription = described_class.new(
          person: person,
          provider: "google",
          sync_scope: "assigned",
          access_token: nil
        )
        expect(subscription.needs_reauthorization?).to be true
      end

      it "returns true when refresh_token is blank and token expired" do
        subscription = described_class.new(
          person: person,
          provider: "google",
          sync_scope: "assigned",
          access_token: "token",
          refresh_token: nil,
          token_expires_at: 1.hour.ago
        )
        expect(subscription.needs_reauthorization?).to be true
      end

      it "returns false when has valid tokens" do
        subscription = described_class.new(
          person: person,
          provider: "google",
          sync_scope: "assigned",
          access_token: "token",
          refresh_token: "refresh",
          token_expires_at: 1.hour.from_now
        )
        expect(subscription.needs_reauthorization?).to be false
      end
    end
  end
end

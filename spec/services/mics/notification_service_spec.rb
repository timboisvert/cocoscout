# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mics::NotificationService do
  before(:all) do
    require Rails.root.join("db", "migrate", "20260603101339_add_mic_queue_notification_templates").to_s
    AddMicQueueNotificationTemplates.new.up
  end

  let(:venue) { create(:venue, name: "Beat Kitchen", city: "Chicago", state: "IL") }
  let(:mic)   { create(:mic, venue: venue, name: "Beat Kitchen Mic") }
  let(:submitter) { create(:user, password: "Password123!") }

  describe ".notify_claim" do
    context "when the hub has a captain" do
      let(:hub)     { create(:city_hub, :active, slug: "chicago-il", name: "Chicago", state: "IL", timezone: "America/Chicago") }
      let(:captain) { create(:user, password: "Password123!") }
      before do
        create(:person, user: captain)
        venue.update!(city_hub: hub)
        create(:city_hub_membership, city_hub: hub, user: captain, role: CityHubMembership.roles[:editor])
      end

      it "sends a message to the captain" do
        claim = create(:mic_claim, mic: mic, claimant: submitter)
        expect {
          described_class.notify_claim(claim: claim)
        }.to change { MessageRecipient.where(recipient: captain.primary_person).count }.by(1)
      end
    end

    context "when no captain exists" do
      it "falls back to a superadmin recipient" do
        admin = create(:user, email_address: "boisvert@gmail.com", password: "Password123!")
        create(:person, user: admin)
        claim = create(:mic_claim, mic: mic, claimant: submitter)
        expect {
          described_class.notify_claim(claim: claim)
        }.to change { MessageRecipient.where(recipient: admin.primary_person).count }.by(1)
      end
    end
  end
end

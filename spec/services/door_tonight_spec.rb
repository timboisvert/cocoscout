# frozen_string_literal: true

require "rails_helper"

# Where a show stands for the door (Tim, 2026-10-16): Andy opened the show's
# page after curtain, tapped its sales link, and found sales closed; the
# Door was far down the page. Pages lead with the Door once it's open.
RSpec.describe DoorTonight do
  let(:org) { create(:organization) }
  let(:friday) { Time.zone.local(2026, 10, 16, 19, 30) }
  let(:show) { create(:show, production: create(:production, organization: org), date_and_time: friday) }
  let(:listing) { create(:ticket_listing, organization: org, show: show) }

  describe ".phase" do
    it "is before the door opens, presale while online sales are on, door once they're over, after at 2 AM" do
      expect(described_class.phase(listing, at: friday - 1.day)).to eq(:before)
      expect(described_class.phase(listing, at: friday.change(hour: 9))).to eq(:presale)
      expect(described_class.phase(listing, at: friday + 35.minutes)).to eq(:door)
      expect(described_class.phase(listing, at: friday.tomorrow.change(hour: 1, min: 30))).to eq(:door)
      expect(described_class.phase(listing, at: friday.tomorrow.change(hour: 2, min: 30))).to eq(:after)
    end

    it "is door as soon as online sales close, before the show starts" do
      listing.update!(status: "closed")
      expect(described_class.phase(listing, at: friday.change(hour: 17))).to eq(:door)
      expect(described_class.door_open?(listing, at: friday.change(hour: 17))).to be(true)
    end

    it "ends an hour after a show with an end time" do
      show.update!(duration_minutes: 60)
      expect(described_class.phase(listing, at: friday + 2.hours)).to eq(:door)
      expect(described_class.phase(listing, at: friday + 2.hours + 15.minutes)).to eq(:after)
    end

    it "has no phase for a draft, a canceled listing or a canceled show" do
      expect(described_class.phase(listing.tap { |l| l.update!(status: "draft") }, at: friday)).to be_nil
      listing.update!(status: "on_sale")
      show.update!(canceled: true)
      expect(described_class.phase(listing.reload, at: friday)).to be_nil
      expect(described_class.door_open?(listing, at: friday)).to be(false)
    end
  end
end

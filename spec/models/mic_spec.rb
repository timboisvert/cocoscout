# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mic, type: :model do
  describe "factory + validations" do
    it "is valid with the factory" do
      expect(build(:mic)).to be_valid
    end

    it "auto-assigns a slug derived from venue + day" do
      v = create(:venue, name: "Lincoln Lodge")
      m = create(:mic, venue: v, day_of_week: 1)
      expect(m.slug).to eq("lincoln-lodge-monday")
    end

    it "increments the slug on collision" do
      v = create(:venue, name: "Lincoln Lodge")
      create(:mic, venue: v, day_of_week: 1)
      m2 = create(:mic, venue: v, day_of_week: 1)
      expect(m2.slug).to eq("lincoln-lodge-monday-2")
    end

    it "rejects bad slug formats" do
      m = build(:mic, slug: "Bad Slug")
      expect(m).not_to be_valid
      expect(m.errors[:slug]).to be_present
    end
  end

  describe "#next_occurrences" do
    it "computes weekly occurrences from day_of_week + starts_local_time when not linked" do
      mic = create(:mic, day_of_week: 1, starts_local_time: "20:00")
      occs = mic.next_occurrences(limit: 4)
      expect(occs.size).to eq(4)
      expect(occs.map { |o| o[:starts_at].wday }.uniq).to eq([ 1 ])
      expect(occs.map { |o| o[:source] }.uniq).to eq([ :computed ])
    end

    it "skips dates before canceled_until" do
      mic = create(:mic, day_of_week: 1, starts_local_time: "20:00",
                          canceled_until: Date.current + 60.days)
      occs = mic.next_occurrences(limit: 3)
      expect(occs.first[:starts_at].to_date).to be > (Date.current + 60.days)
    end
  end

  describe "#powered_by_cocoscout?" do
    it "is false when production_id is nil" do
      expect(build(:mic).powered_by_cocoscout?).to be(false)
    end
  end

  describe "#signup_info" do
    it "returns self-described info when not linked" do
      # Online channel → URL surfaces.
      mic = build(:mic, signup_method: :online, signup_url: "https://forms.gle/abc", signup_opens_at_text: "Mon 9am CT")
      info = mic.signup_info
      expect(info[:url]).to eq("https://forms.gle/abc")
      expect(info[:opens_at_text]).to eq("Mon 9am CT")
      expect(info[:powered_by_cocoscout]).to be(false)
    end

    it "hides the URL when the mic is in-person only" do
      mic = build(:mic, signup_method: :in_person, signup_url: "https://ig.com/foo", signup_opens_at_text: "Walk-in 7:30 PM")
      info = mic.signup_info
      expect(info[:url]).to be_nil
      expect(info[:opens_at_text]).to eq("Walk-in 7:30 PM")
    end

    it "is nil when nothing is configured" do
      expect(build(:mic, signup_url: nil, signup_opens_at_text: nil).signup_info).to be_nil
    end
  end
end

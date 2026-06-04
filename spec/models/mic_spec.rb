# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mic, type: :model do
  describe "factory + validations" do
    it "is valid with the factory" do
      expect(build(:mic)).to be_valid
    end

    it "auto-assigns a slug derived from the mic name" do
      v = create(:venue, name: "Lincoln Lodge")
      m = create(:mic, name: "3 Blind Mice Open Mic", venue: v, day_of_week: 1)
      expect(m.slug).to eq("3-blind-mice-open-mic")
    end

    it "increments the slug on collision" do
      v = create(:venue, name: "Lincoln Lodge")
      create(:mic, name: "3 Blind Mice Open Mic", venue: v, day_of_week: 1)
      m2 = create(:mic, name: "3 Blind Mice Open Mic", venue: v, day_of_week: 2)
      expect(m2.slug).to eq("3-blind-mice-open-mic-2")
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
      expect(occs.first[:starts_at].to_date).to be >= (Date.current + 60.days)
    end

    it "returns explicit custom_dates in order, ignoring past dates" do
      future_a = Date.current + 7
      future_b = Date.current + 14
      past     = Date.current - 1
      mic = create(:mic, recurrence_pattern: :custom_dates,
                          starts_local_time: "20:00",
                          custom_dates: [ future_b.iso8601, past.iso8601, future_a.iso8601 ])
      occs = mic.next_occurrences(limit: 5)
      expect(occs.map { |o| o[:starts_at].to_date }).to eq([ future_a, future_b ])
    end

    it "honors per-entry times for custom_dates so each date can differ" do
      future_a = Date.current + 7
      future_b = Date.current + 14
      mic = create(:mic, recurrence_pattern: :custom_dates,
                          starts_local_time: "20:00",
                          custom_dates: [
                            { "date" => future_a.iso8601, "time" => "19:30" },
                            { "date" => future_b.iso8601, "time" => "21:00" }
                          ])
      occs = mic.next_occurrences(limit: 5)
      expect(occs.map { |o| [ o[:starts_at].to_date, o[:starts_at].strftime("%H:%M") ] }).to eq([
        [ future_a, "19:30" ],
        [ future_b, "21:00" ]
      ])
    end

    it "falls back to starts_local_time when a custom_dates entry has no time" do
      future = Date.current + 7
      mic = create(:mic, recurrence_pattern: :custom_dates,
                          starts_local_time: "20:00",
                          custom_dates: [ { "date" => future.iso8601, "time" => nil } ])
      occs = mic.next_occurrences(limit: 1)
      expect(occs.first[:starts_at].strftime("%H:%M")).to eq("20:00")
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

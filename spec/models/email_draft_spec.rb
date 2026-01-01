# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmailDraft, type: :model do
  describe "associations" do
    it "belongs to emailable optionally" do
      draft = described_class.create!(title: "Test", body: "Body")
      expect(draft.emailable).to be_nil
    end
  end

  describe "validations" do
    it "requires title" do
      draft = described_class.new(title: nil, body: "Body")
      expect(draft).not_to be_valid
    end

    it "requires body" do
      draft = described_class.new(title: "Title", body: nil)
      expect(draft).not_to be_valid
    end
  end

  describe "rich text" do
    it "has rich text body" do
      draft = described_class.new(title: "Test", body: "<p>Hello</p>")
      expect(draft.body.body).to be_present
    end
  end

  describe "polymorphic emailable" do
    let(:show) { create(:show) }

    it "can belong to a Show" do
      draft = described_class.create!(
        title: "Show Reminder",
        body: "Don't forget about the show!",
        emailable: show
      )

      expect(draft.emailable).to eq(show)
      expect(draft.emailable_type).to eq("Show")
    end

    it "can exist without an emailable" do
      draft = described_class.create!(
        title: "General Email",
        body: "Just a test"
      )

      expect(draft.emailable).to be_nil
    end
  end
end

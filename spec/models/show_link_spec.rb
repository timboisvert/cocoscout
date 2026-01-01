# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShowLink, type: :model do
  describe "associations" do
    it "belongs to show" do
      show = create(:show)
      link = described_class.create!(show: show, url: "https://example.com")
      expect(link.show).to eq(show)
    end
  end

  describe "validations" do
    let(:show) { create(:show) }

    it "requires url" do
      link = described_class.new(show: show, url: nil)
      expect(link).not_to be_valid
    end

    describe "url_must_be_safe" do
      it "accepts http URLs" do
        link = described_class.new(show: show, url: "http://example.com")
        expect(link).to be_valid
      end

      it "accepts https URLs" do
        link = described_class.new(show: show, url: "https://example.com")
        expect(link).to be_valid
      end

      it "rejects javascript URLs" do
        link = described_class.new(show: show, url: "javascript:alert('xss')")
        expect(link).not_to be_valid
        expect(link.errors[:url]).to include("must be a valid http or https URL")
      end

      it "rejects invalid URLs" do
        link = described_class.new(show: show, url: "not a url")
        expect(link).not_to be_valid
        expect(link.errors[:url]).to include("is not a valid URL")
      end
    end
  end

  describe "#safe_url" do
    let(:show) { create(:show) }

    it "returns URL for http scheme" do
      link = described_class.new(show: show, url: "http://example.com")
      expect(link.safe_url).to eq("http://example.com")
    end

    it "returns URL for https scheme" do
      link = described_class.new(show: show, url: "https://secure.example.com")
      expect(link.safe_url).to eq("https://secure.example.com")
    end

    it "returns nil for javascript scheme" do
      link = described_class.new(show: show, url: "javascript:void(0)")
      expect(link.safe_url).to be_nil
    end

    it "returns nil for blank URL" do
      link = described_class.new(show: show, url: "")
      expect(link.safe_url).to be_nil
    end

    it "returns nil for invalid URL" do
      link = described_class.new(show: show, url: ":::invalid")
      expect(link.safe_url).to be_nil
    end
  end

  describe "#display_text" do
    let(:show) { create(:show) }

    context "when text is present" do
      it "returns the text" do
        link = described_class.new(show: show, url: "https://example.com", text: "Example Site")
        expect(link.display_text).to eq("Example Site")
      end
    end

    context "when text is blank" do
      it "extracts domain from URL" do
        link = described_class.new(show: show, url: "https://example.com/path")
        expect(link.display_text).to eq("example.com")
      end

      it "returns URL for invalid URIs" do
        link = described_class.new(show: show, url: "invalid")
        expect(link.display_text).to eq("invalid")
      end
    end
  end
end

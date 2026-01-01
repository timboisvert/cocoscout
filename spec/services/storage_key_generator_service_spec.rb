# frozen_string_literal: true

require "rails_helper"

RSpec.describe StorageKeyGeneratorService do
  describe ".generate_key_for_blob" do
    it "returns nil for blob without attachments" do
      blob = instance_double(ActiveStorage::Blob, attachments: [])
      expect(described_class.generate_key_for_blob(blob)).to be_nil
    end
  end

  describe ".generate_key_for_attachment" do
    let(:blob) { instance_double(ActiveStorage::Blob, key: "abc123") }

    context "with ProfileHeadshot record" do
      let(:person) { create(:person) }
      let(:profile_headshot) { create(:profile_headshot, profileable: person) }

      it "generates key with people path" do
        attachment = instance_double(
          ActiveStorage::Attachment,
          name: "image",
          record: profile_headshot,
          blob: blob
        )

        allow(blob).to receive(:key).and_return("abc123")

        key = described_class.generate_key_for_attachment(attachment, blob)
        expect(key).to include("people/")
        expect(key).to include("/headshots/")
      end
    end

    context "with unknown record type" do
      it "uses fallback key" do
        record = instance_double("UnknownRecord", id: 1, class: Class.new { def self.name; "UnknownRecord"; end })
        attachment = instance_double(
          ActiveStorage::Attachment,
          name: "file",
          record: record,
          blob: blob
        )

        key = described_class.generate_key_for_attachment(attachment, blob)
        expect(key).not_to be_nil
      end
    end

    context "with nil record" do
      it "returns nil" do
        attachment = instance_double(
          ActiveStorage::Attachment,
          name: "image",
          record: nil,
          blob: blob
        )

        key = described_class.generate_key_for_attachment(attachment, blob)
        expect(key).to be_nil
      end
    end
  end
end

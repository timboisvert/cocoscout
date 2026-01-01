# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShoutoutExistenceCheckService do
  let(:user) { create(:user) }
  let(:person) { user.person }
  let(:recipient) { create(:person) }

  describe "#call" do
    context "with blank parameters" do
      it "returns false when shoutee_type is blank" do
        service = described_class.new("", recipient.id, user)
        expect(service.call).to be false
      end

      it "returns false when shoutee_id is blank" do
        service = described_class.new("Person", "", user)
        expect(service.call).to be false
      end
    end

    context "when shoutee does not exist" do
      it "returns false for non-existent person" do
        service = described_class.new("Person", 999999, user)
        expect(service.call).to be false
      end

      it "returns false for non-existent group" do
        service = described_class.new("Group", 999999, user)
        expect(service.call).to be false
      end
    end

    context "when no existing shoutout" do
      it "returns false" do
        service = described_class.new("Person", recipient.id, user)
        expect(service.call).to be false
      end
    end

    context "when existing shoutout exists" do
      before do
        create(:shoutout, shouter: person, shoutee: recipient)
      end

      it "returns true" do
        service = described_class.new("Person", recipient.id, user)
        expect(service.call).to be true
      end
    end

    context "when existing shoutout was replaced" do
      before do
        original = create(:shoutout, shouter: person, shoutee: recipient)
        create(:shoutout, shouter: person, shoutee: recipient, replaces: original)
      end

      it "returns true for the replacement shoutout" do
        service = described_class.new("Person", recipient.id, user)
        expect(service.call).to be true
      end
    end
  end
end

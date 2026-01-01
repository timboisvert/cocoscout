# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShoutoutSearchService do
  let(:user) { create(:user) }
  let!(:person1) { create(:person, name: "Alice Smith") }
  let!(:person2) { create(:person, name: "Bob Jones") }
  let!(:person3) { create(:person, name: "Alice Brown") }

  describe "#call" do
    context "with short query" do
      it "returns empty array for single character" do
        service = described_class.new("A", user)
        expect(service.call).to eq([])
      end
    end

    context "with valid query" do
      it "returns matching people" do
        service = described_class.new("Alice", user)
        results = service.call

        expect(results.length).to eq(2)
        expect(results.map { |r| r[:name] }).to include("Alice Smith", "Alice Brown")
      end

      it "excludes current user's person" do
        service = described_class.new(user.person.name[0..3], user)
        results = service.call

        expect(results.map { |r| r[:id] }).not_to include(user.person.id)
      end

      it "is case insensitive" do
        service = described_class.new("alice", user)
        results = service.call

        expect(results.length).to eq(2)
      end

      it "returns results with expected structure" do
        service = described_class.new("Bob", user)
        results = service.call

        expect(results.first).to include(
          type: "Person",
          id: person2.id,
          name: "Bob Jones",
          public_key: person2.public_key
        )
      end
    end

    context "with groups" do
      let!(:group) { create(:group, name: "Alice's Acting Group") }

      before do
        # User is not a member of this group
      end

      it "includes matching groups" do
        service = described_class.new("Alice", user)
        results = service.call

        group_results = results.select { |r| r[:type] == "Group" }
        expect(group_results.map { |r| r[:name] }).to include("Alice's Acting Group")
      end
    end

    it "sorts results by name" do
      service = described_class.new("Alice", user)
      results = service.call

      names = results.map { |r| r[:name] }
      expect(names).to eq(names.sort)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe DirectoryQueryService do
  let(:organization) { create(:organization) }
  let(:production) { create(:production, organization: organization) }
  let!(:person1) { create(:person, name: "Alice Adams") }
  let!(:person2) { create(:person, name: "Bob Brown") }
  let!(:group) { create(:group, name: "Test Group") }

  before do
    organization.people << person1
    organization.people << person2
    organization.groups << group
  end

  describe "#call" do
    it "returns people and groups" do
      service = described_class.new({}, organization)
      people, groups = service.call

      expect(people).to be_a(ActiveRecord::Relation)
      expect(groups).to be_a(ActiveRecord::Relation)
    end

    context "type filter" do
      it "returns only people when type is 'people'" do
        service = described_class.new({ type: "people" }, organization)
        people, groups = service.call

        expect(people.count).to eq(2)
        expect(groups.count).to eq(0)
      end

      it "returns only groups when type is 'groups'" do
        service = described_class.new({ type: "groups" }, organization)
        people, groups = service.call

        expect(people.count).to eq(0)
        expect(groups.count).to eq(1)
      end
    end

    context "search filter" do
      it "filters people by name" do
        service = described_class.new({ q: "Alice" }, organization)
        people, _groups = service.call

        expect(people.pluck(:name)).to eq([ "Alice Adams" ])
      end

      it "filters groups by name" do
        service = described_class.new({ q: "Test" }, organization)
        _people, groups = service.call

        expect(groups.pluck(:name)).to include("Test Group")
      end

      it "is case insensitive" do
        service = described_class.new({ q: "alice" }, organization)
        people, _groups = service.call

        expect(people.pluck(:name)).to eq([ "Alice Adams" ])
      end
    end

    context "sorting" do
      it "sorts alphabetically by default" do
        service = described_class.new({}, organization)
        people, _groups = service.call

        expect(people.pluck(:name)).to eq([ "Alice Adams", "Bob Brown" ])
      end

      it "sorts by newest when specified" do
        service = described_class.new({ order: "newest" }, organization)
        people, _groups = service.call

        expect(people.first.created_at).to be >= people.last.created_at
      end

      it "sorts by oldest when specified" do
        service = described_class.new({ order: "oldest" }, organization)
        people, _groups = service.call

        expect(people.first.created_at).to be <= people.last.created_at
      end
    end

    context "scope filter" do
      let!(:talent_pool) { create(:talent_pool, production: production) }

      before do
        create(:talent_pool_membership, talent_pool: talent_pool, member: person1)
      end

      it "filters by current_production" do
        service = described_class.new({ filter: "current_production" }, organization, production)
        people, _groups = service.call

        expect(people.map(&:id)).to include(person1.id)
      end
    end
  end
end

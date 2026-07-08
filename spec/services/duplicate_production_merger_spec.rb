# frozen_string_literal: true

require "rails_helper"

RSpec.describe DuplicateProductionMerger do
  let(:org) { create(:organization) }
  let(:location) { create(:location, organization: org) }

  describe "Pattern 1 — empty husk + course production on one contract" do
    let(:contract) { create(:contract, organization: org, status: :active) }
    let!(:husk) { create(:production, organization: org, name: "Bootcamp", production_type: :third_party, contract: contract) }
    let!(:course) { create(:production, organization: org, name: "Janelle's Bootcamp", production_type: :course, contract: contract) }
    let!(:show) { create(:show, production: course, location: location) }

    it "keeps the production with shows and deletes the empty husk" do
      result = described_class.new([ husk, course ]).call(dry_run: false)

      expect(result.winner).to eq(course)
      expect(Production.exists?(husk.id)).to be(false)
      expect(course.reload.shows.count).to eq(1)
      expect(contract.reload.productions).to contain_exactly(course)
    end

    it "dry_run makes no changes" do
      expect { described_class.new([ husk, course ]).call(dry_run: true) }
        .not_to change { Production.count }
      expect(Production.exists?(husk.id)).to be(true)
    end
  end

  describe "Pattern 2 — manual in_house + third_party contract production with duplicate shows" do
    let(:contract) { create(:contract, organization: org, status: :active) }
    let(:person) { create(:person) }
    let!(:manual) { create(:production, organization: org, name: "Whatever We Feel", production_type: :in_house) }
    let!(:contract_prod) { create(:production, organization: org, name: "Whatever We Feel", production_type: :third_party, contract: contract) }
    let(:role) { create(:role, production: manual) }
    let(:time) { 1.week.from_now.change(usec: 0) }
    let!(:manual_show) { create(:show, production: manual, location: location, date_and_time: time) }
    let!(:contract_show) { create(:show, production: contract_prod, location: location, date_and_time: time) }

    before { create(:show_person_role_assignment, show: manual_show, role: role, assignable: person) }

    it "picks the production with casting, de-dupes the shared show, moves the contract, deletes the other" do
      result = described_class.new([ manual, contract_prod ]).call(dry_run: false)

      expect(result.winner).to eq(manual) # it has the real casting
      expect(Production.exists?(contract_prod.id)).to be(false)
      expect(manual.reload.shows.count).to eq(1) # duplicate show merged, not doubled
      expect(manual.contract_id).to eq(contract.id)
      expect(manual.show_person_role_assignments.count).to eq(1)
    end
  end

  describe ".duplicate_groups" do
    it "detects same-contract husks and same-name contract duplicates" do
      contract = create(:contract, organization: org, status: :active)
      a = create(:production, organization: org, name: "X", production_type: :third_party, contract: contract)
      b = create(:production, organization: org, name: "Y", production_type: :course, contract: contract)
      # A legitimately-separate same-name pair with NO contract must NOT be grouped.
      create(:production, organization: org, name: "Open Mic")
      create(:production, organization: org, name: "Open Mic")

      groups = described_class.duplicate_groups(org)
      expect(groups.map { |g| g.map(&:id).sort }).to include([ a.id, b.id ].sort)
      expect(groups.flatten.map(&:name)).not_to include("Open Mic")
    end
  end
end

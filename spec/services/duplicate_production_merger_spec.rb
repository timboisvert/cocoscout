# frozen_string_literal: true

require "rails_helper"

RSpec.describe DuplicateProductionMerger do
  let(:org) { create(:organization) }
  let(:location) { create(:location, organization: org) }

  def link(contract, production)
    contract.update!(production: production)
    production
  end

  describe "Pattern 1 — empty husk + course production" do
    let(:contract) { create(:contract, organization: org, status: :active) }
    let!(:course) { link(contract, create(:production, organization: org, name: "Janelle's Bootcamp", production_type: :course)) }
    let!(:husk) { create(:production, organization: org, name: "Bootcamp", production_type: :third_party, contract_id: contract.id) }
    let!(:show) { create(:show, production: course, location: location) }

    it "keeps the production with shows and deletes the empty husk" do
      result = described_class.new([ husk, course ]).call(dry_run: false)

      expect(result.winner).to eq(course)
      expect(Production.exists?(husk.id)).to be(false)
      expect(course.reload.shows.count).to eq(1)
      expect(contract.reload.production).to eq(course)
    end

    it "dry_run makes no changes" do
      expect { described_class.new([ husk, course ]).call(dry_run: true) }.not_to change { Production.count }
      expect(Production.exists?(husk.id)).to be(true)
    end
  end

  describe "Pattern 2 — manual in_house + third_party contract production with duplicate shows" do
    let(:contract) { create(:contract, organization: org, status: :active) }
    let(:person) { create(:person) }
    let!(:manual) { create(:production, organization: org, name: "Whatever We Feel", production_type: :in_house) }
    let!(:contract_prod) { link(contract, create(:production, organization: org, name: "Whatever We Feel", production_type: :third_party)) }
    let(:role) { create(:role, production: manual) }
    let(:time) { 1.week.from_now.change(usec: 0) }
    let!(:manual_show) { create(:show, production: manual, location: location, date_and_time: time) }
    let!(:contract_show) { create(:show, production: contract_prod, location: location, date_and_time: time) }

    before { create(:show_person_role_assignment, show: manual_show, role: role, assignable: person) }

    it "keeps the production with casting, de-dupes the show, re-points the contract, deletes the other" do
      result = described_class.new([ manual, contract_prod ]).call(dry_run: false)

      expect(result.winner).to eq(manual)
      expect(Production.exists?(contract_prod.id)).to be(false)
      expect(manual.reload.shows.count).to eq(1)
      expect(manual.contracts).to contain_exactly(contract)
      expect(manual.show_person_role_assignments.count).to eq(1)
    end
  end

  describe "Pattern 3 — two valid contracts for the same show (merge onto one production)" do
    let(:contract_a) { create(:contract, organization: org, status: :active) }
    let(:contract_b) { create(:contract, organization: org, status: :active) }
    let!(:prod_a) { link(contract_a, create(:production, organization: org, name: "The Real Spacewives of Alderaan", production_type: :third_party)) }
    let!(:prod_b) { link(contract_b, create(:production, organization: org, name: "The Real Spacewives of Alderaan", production_type: :third_party)) }
    let!(:show_a) { create(:show, production: prod_a, location: location, date_and_time: 1.week.from_now.change(usec: 0)) }
    let!(:show_b) { create(:show, production: prod_b, location: location, date_and_time: 3.weeks.from_now.change(usec: 0)) }

    it "collapses to ONE production that carries BOTH contracts (nothing lost)" do
      result = described_class.new([ prod_a, prod_b ]).call(dry_run: false)

      winner = result.winner
      loser = ([ prod_a, prod_b ] - [ winner ]).first

      expect(Production.exists?(loser.id)).to be(false)
      expect(Production.exists?(winner.id)).to be(true)
      # Both contracts now point at the surviving production, so both revenues resolve.
      expect(winner.reload.contracts).to contain_exactly(contract_a, contract_b)
      expect(contract_a.reload.production).to eq(winner)
      expect(contract_b.reload.production).to eq(winner)
      # Both distinct dates survive on the one production.
      expect(winner.shows.count).to eq(2)
    end
  end

  describe ".coalesce" do
    it "unions overlapping groups so each production appears in exactly one group" do
      a = create(:production, organization: org)
      b = create(:production, organization: org)
      c = create(:production, organization: org)
      d = create(:production, organization: org)

      # Chain that the old single-pass got wrong: {a,b} and {c,d} both connect to {b,c}.
      groups = described_class.coalesce([ [ a, b ], [ c, d ], [ b, c ] ])

      expect(groups.size).to eq(1)
      expect(groups.first.map(&:id).sort).to eq([ a, b, c, d ].map(&:id).sort)
    end
  end

  describe ".duplicate_groups" do
    it "detects same-contract husks and same-name contract duplicates, ignoring non-contract same-names" do
      contract = create(:contract, organization: org, status: :active)
      # Existing husk-bug data: both productions carry the legacy contract_id column.
      a = create(:production, organization: org, name: "X", production_type: :third_party, contract_id: contract.id)
      b = create(:production, organization: org, name: "Y", production_type: :course, contract_id: contract.id)
      create(:production, organization: org, name: "Open Mic")
      create(:production, organization: org, name: "Open Mic")

      groups = described_class.duplicate_groups(org)
      expect(groups.map { |g| g.map(&:id).sort }).to include([ a.id, b.id ].sort)
      expect(groups.flatten.map(&:name)).not_to include("Open Mic")
    end
  end
end

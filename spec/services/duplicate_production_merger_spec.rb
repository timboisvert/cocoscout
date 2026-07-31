# frozen_string_literal: true

require "rails_helper"

RSpec.describe DuplicateProductionMerger, type: :service do
  let(:org) { create(:organization, :pro) } # Pro allows more than one production
  let(:keeper) { create(:production, organization: org, name: "Improv Bootcamp") }
  let(:loser)  { create(:production, organization: org, name: "Improv Bootcamp") }

  it "re-points children onto the keeper and deletes the loser" do
    show = create(:show, production: loser)
    contract = create(:contract, organization: org, production: loser, production_name: nil)
    offering = create(:course_offering, production: loser)

    result = described_class.call(keeper_id: keeper.id, loser_ids: [ loser.id ])

    expect(Production.exists?(loser.id)).to be false
    expect(show.reload.production_id).to eq(keeper.id)
    expect(offering.reload.production_id).to eq(keeper.id)
    expect(contract.reload.production_id).to eq(keeper.id)
    # Denormalized snapshot is refreshed to the keeper's name.
    expect(contract.production_name).to eq(keeper.name)
    expect(result.merged_loser_ids).to eq([ loser.id ])
    expect(result.moved["shows"]).to eq(1)
  end

  it "drops rows that would collide with a unique index on the keeper" do
    user = create(:user)
    ProductionPermission.create!(user: user, production: keeper, role: "manager")
    ProductionPermission.create!(user: user, production: loser, role: "manager")

    result = described_class.call(keeper_id: keeper.id, loser_ids: [ loser.id ])

    # The loser's permission was redundant — one permission survives, not two.
    expect(ProductionPermission.where(user: user, production: keeper).count).to eq(1)
    expect(result.deduped["production_permissions"]).to eq(1)
    expect(Production.exists?(loser.id)).to be false
  end

  it "swaps the loser id for the keeper in users' included_production_ids arrays" do
    user = create(:user)
    user.update_column(:included_production_ids, [ loser.id, 9999 ])

    described_class.call(keeper_id: keeper.id, loser_ids: [ loser.id ])

    expect(user.reload.included_production_ids).to include(keeper.id)
    expect(user.included_production_ids).not_to include(loser.id)
    expect(user.included_production_ids).to include(9999) # untouched entries preserved
  end

  it "refuses to merge productions from a different organization" do
    other_org_loser = create(:production, organization: create(:organization))

    expect {
      described_class.call(keeper_id: keeper.id, loser_ids: [ other_org_loser.id ])
    }.to raise_error(ArgumentError, /across orgs/)

    expect(Production.exists?(other_org_loser.id)).to be true
  end

  it "dry_run reports the tallies but leaves the database untouched" do
    show = create(:show, production: loser)

    result = described_class.call(keeper_id: keeper.id, loser_ids: [ loser.id ], dry_run: true)

    expect(result.dry_run).to be true
    expect(result.moved["shows"]).to eq(1)
    # Nothing actually changed:
    expect(Production.exists?(loser.id)).to be true
    expect(show.reload.production_id).to eq(loser.id)
  end

  it "is a no-op when the keeper id is also passed as a loser" do
    keeper # force-create before measuring the count
    expect {
      described_class.call(keeper_id: keeper.id, loser_ids: [ keeper.id ])
    }.not_to change(Production, :count)
    expect(Production.exists?(keeper.id)).to be true
  end
end

# frozen_string_literal: true

require "rails_helper"

# A single document can apply to several productions, and "Production team"
# sharing is satisfied by the team of ANY production it applies to.
RSpec.describe "ProductionDocument multi-production", type: :model do
  let(:org) { create(:organization) }
  let(:home)  { create(:production, organization: org, name: "Starlet") }
  let(:other) { create(:production, organization: org, name: "Rising Stars") }
  let(:user) { create(:user) }
  let!(:person) { create(:person, user: user) }

  it "is visible to the team of a non-home production it also applies to" do
    # The user manages only `other`, not the document's home production.
    ProductionPermission.create!(user: user, production: other, role: "manager")

    doc = home.documents.create!(title: "Performer Handbook", body: "<div>x</div>")
    doc.apply_default_sharing! # shared with the production team

    # Only applies to `home` so far — the user isn't on that team.
    expect(doc.visible_to?(person)).to be(false)

    doc.set_productions!([ home.id, other.id ])
    doc.reload

    expect(doc.visible_to?(person)).to be(true)
    expect(person.accessible_production_documents).to include(doc)
  end

  it "keeps a valid home when the primary production is removed from the set" do
    doc = home.documents.create!(title: "Handbook", body: "<div>x</div>")
    doc.set_productions!([ other.id ])
    expect(doc.reload.production).to eq(other)
    expect(doc.applies_to_production_ids).to contain_exactly(other.id)
  end

  it "never empties the applies-to set" do
    doc = home.documents.create!(title: "Handbook", body: "<div>x</div>")
    doc.set_productions!([])
    expect(doc.reload.applies_to_production_ids).to contain_exactly(home.id)
  end
end

# frozen_string_literal: true

require "rails_helper"

# Visibility (who can see/edit) for ProductionDocument across every share kind:
# team, talent pool, specific person — at read and write permission.
RSpec.describe "ProductionDocument sharing & visibility", type: :model do
  let(:org) { create(:organization) }
  let(:production) { create(:production, organization: org) }
  let(:doc) { production.documents.create!(title: "Handbook", body: "<div>x</div>") }

  def pool_member(pool)
    create(:person).tap { |p| pool.talent_pool_memberships.create!(member: p) }
  end

  describe "team sharing" do
    it "is visible and writable to a production manager" do
      user = create(:user)
      person = create(:person, user: user)
      ProductionPermission.create!(user: user, production: production, role: "manager")
      doc.apply_default_sharing! # team · write

      expect(doc.visible_to?(person)).to be(true)
      expect(doc.writable_by?(person)).to be(true)
      expect(person.accessible_production_documents).to include(doc)
    end

    it "is read-only when the team share is read" do
      user = create(:user)
      person = create(:person, user: user)
      ProductionPermission.create!(user: user, production: production, role: "manager")
      doc.set_sharing!(team: { enabled: "1", permission: "read" }, talent_pools: {}, people: {})

      expect(doc.visible_to?(person)).to be(true)
      expect(doc.writable_by?(person)).to be(false)
    end

    it "is hidden from someone with no role on the production" do
      outsider = create(:person, user: create(:user))
      doc.apply_default_sharing!
      expect(doc.visible_to?(outsider)).to be(false)
    end
  end

  describe "talent pool sharing" do
    it "is visible to pool members, hidden from outsiders" do
      pool = production.talent_pool
      member = pool_member(pool)
      outsider = create(:person)
      doc.set_sharing!(team: { enabled: false }, talent_pools: { pool.id.to_s => { enabled: "1", permission: "read" } }, people: {})

      expect(doc.visible_to?(member)).to be(true)
      expect(doc.writable_by?(member)).to be(false) # read share
      expect(doc.visible_to?(outsider)).to be(false)
    end

    it "grants write when the pool share is write" do
      pool = production.talent_pool
      member = pool_member(pool)
      doc.set_sharing!(team: { enabled: false }, talent_pools: { pool.id.to_s => { enabled: "1", permission: "write" } }, people: {})
      expect(doc.writable_by?(member)).to be(true)
    end
  end

  describe "specific-person sharing" do
    it "is visible only to the named person" do
      a = create(:person)
      b = create(:person)
      doc.set_sharing!(team: { enabled: false }, talent_pools: {}, people: { a.id.to_s => "read" })

      expect(doc.visible_to?(a)).to be(true)
      expect(doc.visible_to?(b)).to be(false)
    end
  end

  describe "apply_default_sharing!" do
    it "shares with the team (write) and is idempotent" do
      doc.apply_default_sharing!
      doc.apply_default_sharing!
      expect(doc.shares.where(audience_type: "team").count).to eq(1)
      expect(doc.team_permission).to eq("write")
    end
  end

  describe "set_sharing! rebuild" do
    it "replaces previous grants wholesale" do
      doc.apply_default_sharing!
      a = create(:person)
      doc.set_sharing!(team: { enabled: false }, talent_pools: {}, people: { a.id.to_s => "write" })

      expect(doc.reload.shared_with_team?).to be(false)
      expect(doc.person_share_ids).to eq([ a.id ])
      expect(doc.person_permission(a.id)).to eq("write")
    end
  end

  describe "audience_summary" do
    it "names each kind of grant" do
      pool = production.talent_pool
      a = create(:person)
      doc.set_sharing!(
        team: { enabled: "1", permission: "write" },
        talent_pools: { pool.id.to_s => { enabled: "1", permission: "read" } },
        people: { a.id.to_s => "read" }
      )
      summary = doc.audience_summary
      expect(summary).to include("Production team")
      expect(summary).to include("1 talent pool")
      expect(summary).to include("1 person")
    end
  end
end

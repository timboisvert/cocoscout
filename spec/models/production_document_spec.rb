# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductionDocument, type: :model do
  let(:production) { create(:production) }
  let(:document) { production.documents.create!(title: "Doc", body: "<div>x</div>") }

  describe "#apply_default_sharing!" do
    it "shares with the production team (write) by default" do
      document.apply_default_sharing!
      document.reload
      expect(document.shared_with_team?).to be(true)
      expect(document.team_permission).to eq("write")
    end
  end

  describe "#visible_to? / #writable_by?" do
    it "team (write) → visible and writable to a team member" do
      document.set_sharing!(team: { enabled: true, permission: "write" }, talent_pools: {}, people: {})
      user = create(:user)
      person = create(:person, user: user)
      ProductionPermission.create!(user: user, production: production, role: "manager")

      expect(document.visible_to?(person)).to be(true)
      expect(document.writable_by?(person)).to be(true)
    end

    it "talent pool (read) → visible but not writable; strangers excluded" do
      pool = production.talent_pool
      document.set_sharing!(team: { enabled: false }, talent_pools: { pool.id.to_s => { enabled: true, permission: "read" } }, people: {})
      member = create(:person)
      pool.talent_pool_memberships.create!(member: member)

      expect(document.visible_to?(member)).to be(true)
      expect(document.writable_by?(member)).to be(false)
      expect(document.visible_to?(create(:person))).to be(false)
    end

    it "specific person (write) → visible and writable to just that person" do
      person = create(:person)
      document.set_sharing!(team: { enabled: false }, talent_pools: {}, people: { person.id.to_s => "write" })

      expect(document.visible_to?(person)).to be(true)
      expect(document.writable_by?(person)).to be(true)
      expect(document.visible_to?(create(:person))).to be(false)
    end
  end

  describe "#audience_summary" do
    it "summarizes configured audiences" do
      pool = production.talent_pool
      document.set_sharing!(
        team: { enabled: true, permission: "write" },
        talent_pools: { pool.id.to_s => { enabled: true, permission: "read" } },
        people: { create(:person).id.to_s => "read" }
      )
      expect(document.audience_summary).to eq("Production team · 1 talent pool · 1 person")
    end
  end
end

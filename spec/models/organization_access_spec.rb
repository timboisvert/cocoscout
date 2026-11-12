# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrganizationAccess do
  let(:organization) { create(:organization) }
  let(:user) { create(:user) }

  describe ".level" do
    it "gives the owner everything" do
      expect(described_class.level(organization.owner, organization, :books)).to eq("manage")
    end

    it "gives a manager everything" do
      create(:organization_role, user: user, organization: organization, company_role: "manager")
      expect(described_class.level(user, organization, :payouts)).to eq("manage")
      expect(described_class.governed?(user, organization)).to be(false)
    end

    it "reads a viewer without grants the old way: free modules to view, no Pro" do
      create(:organization_role, user: user, organization: organization, company_role: "viewer")
      expect(described_class.level(user, organization, :shows)).to eq("view")
      expect(described_class.level(user, organization, :books)).to eq("none")
      expect(described_class.governed?(user, organization)).to be(false)
    end

    it "reads a viewer with grants from the grid" do
      role = create(:organization_role, user: user, organization: organization, company_role: "viewer")
      role.apply_access!(template: "bookkeeper")
      expect(described_class.governed?(user, organization)).to be(true)
      expect(described_class.level(user, organization, :books)).to eq("manage")
      expect(described_class.level(user, organization, :payouts)).to eq("view")
      expect(described_class.level(user, organization, :ticketing)).to eq("none")
      expect(described_class.level(user, organization, :productions)).to eq("view")
      expect(described_class.money_level(user, organization)).to eq("manage")
      expect(role.access_label).to eq("Bookkeeper")
    end

    it "gives someone off the team nothing" do
      expect(described_class.level(user, organization, :shows)).to eq("none")
    end
  end

  describe ".template_for and apply_access!" do
    it "names a grid that matches a template, else Custom" do
      expect(described_class.template_for(described_class.grants_for_template("accountant"))).to eq("accountant")
      custom = described_class.grants_for_template("accountant").merge("ticketing" => "view")
      expect(described_class.template_for(custom)).to eq("custom")
    end

    it "keeps Home and productions at least view" do
      expect(described_class.normalize({ "productions" => "none", "books" => "manage", "bogus" => "manage" }))
        .to eq({ "productions" => "view", "books" => "manage" })
    end

    it "turns a manager into a viewer with a grid, and back" do
      role = create(:organization_role, user: user, organization: organization, company_role: "manager")
      role.apply_access!(template: "box_office")
      expect(role.reload.company_role).to eq("viewer")
      expect(role.module_grants["door"]).to eq("manage")
      role.apply_access!(template: "manager")
      expect(role.reload.company_role).to eq("manager")
      expect(role.module_grants).to eq({})
      expect(role.access_template).to be_nil
    end
  end
end

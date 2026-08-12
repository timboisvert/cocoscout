# frozen_string_literal: true

require "rails_helper"

RSpec.describe SchedulingRule, type: :model do
  let(:organization) { create(:organization) }

  describe "per-type validations" do
    it "requires a production for a production-anchored rule" do
      rule = build(:scheduling_rule, organization: organization, production: nil)
      expect(rule).not_to be_valid
      expect(rule.errors[:production]).to be_present
    end

    it "requires day and times for a weekday rule" do
      rule = build(:scheduling_rule, :weekday, organization: organization,
                                               day_of_week: nil, starts_local_time: nil, ends_local_time: nil)
      expect(rule).not_to be_valid
      expect(rule.errors[:day_of_week]).to be_present
      expect(rule.errors[:starts_local_time]).to be_present
      expect(rule.errors[:ends_local_time]).to be_present
    end

    it "rejects a day of week outside 0..6" do
      rule = build(:scheduling_rule, :weekday, organization: organization, day_of_week: 7)
      expect(rule).not_to be_valid
    end
  end

  describe "org scoping" do
    it "rejects a production from another organization" do
      rule = build(:scheduling_rule, organization: organization, production: create(:production))
      expect(rule).not_to be_valid
      expect(rule.errors[:production].join).to include("must belong to this organization")
    end

    it "rejects a house role from another organization" do
      rule = build(:scheduling_rule, organization: organization, house_role: create(:house_role))
      expect(rule).not_to be_valid
      expect(rule.errors[:house_role].join).to include("must belong to this organization")
    end

    it "rejects a person who isn't an active staff member" do
      outsider = create(:person)
      rule = build(:scheduling_rule, organization: organization)
      rule.person = outsider
      expect(rule).not_to be_valid
      expect(rule.errors[:person].join).to include("active staff member")
    end

    it "rejects a person whose staff membership is archived" do
      person = create(:person)
      create(:organization_staff_member, :archived, organization: organization, person: person)
      rule = build(:scheduling_rule, organization: organization)
      rule.person = person
      expect(rule).not_to be_valid
    end
  end

  describe "duplicate guard" do
    it "rejects a second identical active rule" do
      existing = create(:scheduling_rule, organization: organization)
      dupe = build(:scheduling_rule, organization: organization,
                                     person: existing.person,
                                     house_role: existing.house_role,
                                     production: existing.production)
      expect(dupe).not_to be_valid
      expect(dupe.errors[:base].join).to include("already a rule like this")
    end

    it "allows the same rule again once the first is archived" do
      existing = create(:scheduling_rule, organization: organization)
      existing.update!(archived_at: Time.current)
      dupe = build(:scheduling_rule, organization: organization,
                                     person: existing.person,
                                     house_role: existing.house_role,
                                     production: existing.production)
      expect(dupe).to be_valid
    end
  end

  describe "#target_label" do
    it "names the production for a production-anchored rule" do
      rule = build(:scheduling_rule, organization: organization)
      expect(rule.target_label).to eq(rule.production.name)
    end

    it "describes the weekday window for a weekday rule" do
      rule = build(:scheduling_rule, :weekday, organization: organization)
      expect(rule.target_label).to eq("Thursdays 6:00 PM – 10:00 PM")
    end
  end
end
